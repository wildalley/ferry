package ferryregression

import (
	"testing"
	"time"

	"github.com/sagernet/quic-go/congestion"
	brutal "github.com/sagernet/sing-quic/hysteria/congestion"
)

type fixedRTT struct {
	congestion.RTTStatsProvider
	rtt time.Duration
}

func (r fixedRTT) SmoothedRTT() time.Duration { return r.rtt }

func TestBrutalLowRTTProgress(t *testing.T) {
	for _, rtt := range []time.Duration{time.Nanosecond, time.Microsecond, 10 * time.Microsecond} {
		for _, size := range []congestion.ByteCount{1252, 1400} {
			sender := brutal.NewBrutalSender(100*1000*1000/8, false, nil)
			sender.SetRTTStatsProvider(fixedRTT{rtt: rtt})
			sender.SetMaxDatagramSize(size)
			if sender.GetCongestionWindow() < size {
				t.Fatalf("RTT %s: window %d cannot fit datagram %d", rtt, sender.GetCongestionWindow(), size)
			}
			// The receiver may delay its ACK until a second datagram arrives.
			// Keep progress possible when the first occupies the entire window.
			if !sender.CanSend(size) {
				t.Fatalf("RTT %s: cannot progress with one %d-byte datagram in flight", rtt, size)
			}
			if sender.CanSend(sender.GetCongestionWindow() + 1) {
				t.Fatal("sender ignores the congestion window")
			}
		}
	}
}

func TestBrutalNormalRTTKeepsBandwidthWindow(t *testing.T) {
	sender := brutal.NewBrutalSender(100*1000*1000/8, false, nil)
	sender.SetRTTStatsProvider(fixedRTT{rtt: 20 * time.Millisecond})
	if got := sender.GetCongestionWindow(); got != 500000 {
		t.Fatalf("normal RTT bandwidth window changed: %d", got)
	}
}
