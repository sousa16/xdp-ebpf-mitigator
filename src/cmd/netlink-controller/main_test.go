package main

import (
	"net"
	"runtime"
	"testing"

	"github.com/vishvananda/netlink"
	"github.com/vishvananda/netns"
)

func TestNetworkInfrastructure(t *testing.T) {
	// Pin to thread because we are touching namespaces
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	// 0. Save the current (host) namespace so we can return to it
	originNS, err := netns.Get()
	if err != nil {
		t.Fatalf("Failed to get original namespace: %v", err)
	}
	defer originNS.Close()
	defer func() {
		if err := netns.Set(originNS); err != nil {
			t.Errorf("CRITICAL: failed to restore host namespace: %v", err)
		}
	}()

	// 1. Test Namespace Existence
	// Open and immediately close — we just want to confirm it exists.
	// We'll open it properly in step 3.
	existingNS, err := netns.GetFromName("mitigator-ns")
	if err != nil {
		t.Fatalf("Namespace 'mitigator-ns' not found: %v", err)
	}
	existingNS.Close()

	// 2. Test Host-side Veth
	link, err := netlink.LinkByName("veth-host")
	if err != nil {
		t.Errorf("veth-host missing from host: %v", err)
	} else {
		// Check IFF_UP via Flags. net.FlagUp (0x1) maps to IFF_UP.
		// For veth pairs, OperState may be OperUnknown when the peer is in another
		// namespace, so we check Flags rather than OperState here.
		attrs := link.Attrs()
		adminUp := (attrs.Flags & net.FlagUp) != 0
		// OperUp or OperUnknown are both acceptable for a veth whose peer is in a
		// different namespace (kernel cannot always resolve carrier state cross-ns).
		operOK := attrs.OperState == netlink.OperUp || attrs.OperState == netlink.OperUnknown
		if !adminUp || !operOK {
			t.Errorf("veth-host does not appear UP (Flags: %v, OperState: %v). Ensure LinkSetUp was called.",
				attrs.Flags, attrs.OperState)
		}
	}

	// 3. Test Namespace-side Veth
	ns, err := netns.GetFromName("mitigator-ns")
	if err != nil {
		t.Fatalf("Failed to get mitigator-ns handle: %v", err)
	}
	defer ns.Close()

	// Hop inside the namespace
	if err := netns.Set(ns); err != nil {
		t.Fatalf("Failed to enter namespace for testing: %v", err)
	}

	peer, err := netlink.LinkByName("veth-ns")
	if err != nil {
		t.Errorf("veth-ns missing inside namespace: %v", err)
	} else {
		// Same logic as host side: accept OperUnknown for cross-namespace veth
		attrs := peer.Attrs()
		adminUp := (attrs.Flags & net.FlagUp) != 0
		operOK := attrs.OperState == netlink.OperUp || attrs.OperState == netlink.OperUnknown
		if !adminUp || !operOK {
			t.Errorf("veth-ns inside namespace is DOWN (Flags: %v, OperState: %v)", attrs.Flags, attrs.OperState)
		}
	}

	// Explicitly return to host namespace before defers fire,
	// so any subsequent test cleanup runs in the correct context.
	if err := netns.Set(originNS); err != nil {
		t.Fatalf("CRITICAL: failed to return to host namespace after namespace tests: %v", err)
	}
}
