package ferryregression

import (
	"runtime/debug"
	"testing"

	"github.com/sagernet/sing-box/experimental/libbox"
)

func TestAndroidMemoryPolicySurvivesCoreUpgrade(t *testing.T) {
	previous := debug.SetGCPercent(100)
	defer debug.SetGCPercent(previous)
	libbox.ConfigureFerryMemory()
	if actual := debug.SetGCPercent(100); actual != 10 {
		t.Fatalf("Android GC policy changed: got %d, want 10", actual)
	}
}
