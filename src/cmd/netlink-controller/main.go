package main

import (
	"fmt"
	"runtime"

	"github.com/vishvananda/netlink"
	"github.com/vishvananda/netns"
)

func main() {
	// 1. Lock thread for namespace stability
	runtime.LockOSThread()
	defer runtime.UnlockOSThread()

	// 2. Capture host namespace FIRST, before any namespace operations.
	hostNS, err := netns.Get()
	if err != nil {
		fmt.Printf("Failed to get host namespace: %v\n", err)
		return
	}
	defer hostNS.Close()

	// Create a netlink handle scoped to the host namespace.
	// All host-side link operations use this handle — never the default
	// netlink functions, which operate on whatever namespace the thread
	// happens to be in at call time.
	hostHandle, err := netlink.NewHandleAt(hostNS)
	if err != nil {
		fmt.Printf("Failed to create host netlink handle: %v\n", err)
		return
	}
	defer hostHandle.Delete()

	// 3. Namespace Reconciliation
	ns, err := netns.GetFromName("mitigator-ns")
	if err != nil {
		fmt.Println("Namespace not found, creating it...")
		ns, err = netns.NewNamed("mitigator-ns")
		if err != nil {
			fmt.Printf("Error creating namespace: %v\n", err)
			return
		}
	} else {
		fmt.Println("Namespace 'mitigator-ns' already exists.")
	}
	defer ns.Close()

	// Create a netlink handle scoped to the target namespace.
	nsHandle, err := netlink.NewHandleAt(ns)
	if err != nil {
		fmt.Printf("Failed to create namespace netlink handle: %v\n", err)
		return
	}
	defer nsHandle.Delete()

	// 4. Veth Reconciliation — use hostHandle so we always look at the host.
	_, err = hostHandle.LinkByName("veth-host")
	if err != nil {
		fmt.Println("veth-host not found on host, creating pair...")

		veth := &netlink.Veth{
			LinkAttrs: netlink.LinkAttrs{Name: "veth-host"},
			PeerName:  "veth-ns",
		}
		// LinkAdd via hostHandle — both ends are created on the host first.
		if err := hostHandle.LinkAdd(veth); err != nil {
			fmt.Printf("Error creating veth pair: %v\n", err)
			return
		}
		// Fetch the peer from the host side.
		peer, err := hostHandle.LinkByName("veth-ns")
		if err != nil {
			fmt.Printf("Could not find veth-ns after creation: %v\n", err)
			return
		}
		// Move ONLY the peer into the namespace.
		if err := hostHandle.LinkSetNsFd(peer, int(ns)); err != nil {
			fmt.Printf("Failed to move veth-ns to namespace: %v\n", err)
			return
		}
		fmt.Println("veth pair created and veth-ns moved to mitigator-ns.")
	} else {
		fmt.Println("veth-host already exists on host.")
		// Verify the peer is actually inside the namespace.
		_, peerErr := nsHandle.LinkByName("veth-ns")
		if peerErr != nil {
			fmt.Printf("Warning: veth-host exists on host but veth-ns not found in namespace: %v\n", peerErr)
			fmt.Println("You may need to manually clean up and re-run.")
			return
		}
	}

	// 5. Bring up the namespace-side veth using the ns-scoped handle.
	peerInNs, err := nsHandle.LinkByName("veth-ns")
	if err != nil {
		fmt.Printf("Could not find veth-ns inside namespace: %v\n", err)
		return
	}
	if err := nsHandle.LinkSetUp(peerInNs); err != nil {
		fmt.Printf("Failed to bring veth-ns up: %v\n", err)
		return
	}

	// 6. Bring up the host-side veth using the host-scoped handle.
	hostVeth, err := hostHandle.LinkByName("veth-host")
	if err != nil {
		fmt.Printf("Error: veth-host not found on host: %v\n", err)
		return
	}
	if err := hostHandle.LinkSetUp(hostVeth); err != nil {
		fmt.Printf("Failed to bring veth-host up: %v\n", err)
		return
	}

	fmt.Println("--- Network Infrastructure Synchronized ---")
}
