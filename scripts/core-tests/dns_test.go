package ferryregression

import (
	"context"
	"net"
	"testing"
	"time"

	mDNS "github.com/miekg/dns"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/dns/transport"
	"github.com/sagernet/sing-box/log"
	"github.com/sagernet/sing-box/option"
)

// Exercise the shipped transports over real loopback sockets. No external DNS
// queries, host resolver changes, privileged ports, or TUN devices are needed.
func TestDNSLoopbackTransports(t *testing.T) {
	tcp, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { tcp.Close() })
	udp, err := net.ListenPacket("udp4", tcp.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { udp.Close() })
	handler := mDNS.HandlerFunc(func(w mDNS.ResponseWriter, request *mDNS.Msg) {
		if request.Question[0].Name == "timeout.test." {
			return
		}
		response := new(mDNS.Msg).SetReply(request)
		if _, isUDP := w.RemoteAddr().(*net.UDPAddr); isUDP && request.Question[0].Name == "truncated.test." {
			response.Truncated = true
		} else {
			response.Answer = []mDNS.RR{&mDNS.A{
				Hdr: mDNS.RR_Header{Name: request.Question[0].Name, Rrtype: mDNS.TypeA, Class: mDNS.ClassINET, Ttl: 60},
				A:   net.IPv4(192, 0, 2, 7),
			}}
		}
		if err := w.WriteMsg(response); err != nil {
			t.Errorf("DNS server: %v", err)
		}
	})
	for _, server := range []*mDNS.Server{
		{Listener: tcp, Handler: handler},
		{PacketConn: udp, Handler: handler},
	} {
		ready, done := make(chan struct{}), make(chan error, 1)
		server.NotifyStartedFunc = func() { close(ready) }
		go func() { done <- server.ActivateAndServe() }()
		select {
		case <-ready:
		case err := <-done:
			t.Fatalf("start DNS server: %v", err)
		case <-time.After(5 * time.Second):
			t.Fatal("DNS server did not start")
		}
		t.Cleanup(func() {
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			if err := server.ShutdownContext(ctx); err != nil {
				t.Errorf("stop DNS server: %v", err)
			}
			select {
			case err := <-done:
				if err != nil {
					t.Errorf("DNS server: %v", err)
				}
			case <-ctx.Done():
				t.Error("DNS server did not stop")
			}
		})
	}
	options := option.RemoteDNSServerOptions{DNSServerAddressOptions: option.DNSServerAddressOptions{
		Server: "127.0.0.1", ServerPort: uint16(tcp.Addr().(*net.TCPAddr).Port),
	}}
	for _, protocol := range []string{"udp", "tcp"} {
		t.Run(protocol, func(t *testing.T) {
			create := transport.NewUDP
			if protocol == "tcp" {
				create = transport.NewTCP
			}
			client, err := create(context.Background(), log.NewNOPFactory().Logger(), "test", options)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { client.Close() })
			if err := client.Start(adapter.StartStateStart); err != nil {
				t.Fatal(err)
			}
			// Query after both Reset and a timeout to catch stale connection or
			// callback state, including UDP-to-TCP truncation fallback.
			for _, name := range []string{"answer.test.", "truncated.test.", "timeout.test.", "recovered.test."} {
				ctx, cancel := context.WithTimeout(context.Background(), time.Second)
				if name == "timeout.test." {
					cancel()
					ctx, cancel = context.WithTimeout(context.Background(), 100*time.Millisecond)
				}
				response, err := client.Exchange(ctx, new(mDNS.Msg).SetQuestion(name, mDNS.TypeA))
				cancel()
				if name == "timeout.test." {
					if err == nil {
						t.Fatal("unanswered DNS query did not fail")
					}
					continue
				}
				if err != nil {
					t.Fatalf("%s: %v", name, err)
				}
				if len(response.Answer) != 1 || response.Truncated || response.Answer[0].(*mDNS.A).A.String() != "192.0.2.7" {
					t.Fatalf("%s: unexpected response: %s", name, response)
				}
				if name == "answer.test." {
					client.Reset()
				}
			}
		})
	}
}
