eBPF: Extended Berkeley Packet FIlter
Makes the kernel programmable

![eBPF](/docs/images/getting-started-with-ebpf/ebpf-basics/ebpf.png)

eBPF programs are event-triggered, and can be attached to many types of events:
1. Kprobes - allows developers and administrators to insert debugging or performance-monitoring code at almost any kernel address, function entry, or return point without recompiling or rebooting
2. Uprobes
3. Tracepoints
4. **Network packets**
5. Linux Security Module
6. Perf events
7. ... and more

**Why does eBPF matter:** upstream kernel changes take years to reach popular Linux distributions <br>
Used for customized behavior that doesn't have to meet general purpose needs

Example: Vuln Mitigation - Packet of Death <br>
A crafted network packet can crash the system

![Packet of Death](/docs/images/getting-started-with-ebpf/ebpf-basics/packet-of-death.png)

With eBPF, we can write a program that spots this packet and discards it before it ever reaches the kernel's network stack, without having to go through the process of patching this in the Linux kernel.

eBPF Verifier ensures programs can't crash or hang the kernel

**eBPF Hello World**: whenever you run a program/command, it calls the **execve** system call. <br>
This code uses that to run "hello world" every time a program runs.

![eBPF Hello World](/docs/images/getting-started-with-ebpf/ebpf-basics/ebpf-helloworld.png)

Things to notice:
1. Context *ctx* depends on the event
2. *bpf_trace_printk()* always writes to */sys/kerneldebug/tracing/trace_pipe*
   It's an example of an eBPF helper function
   If we have multiple eBPF programs running, they all write to the same file. There are better ways to get information in and out of eBPF programs

**eBPF Maps**: a better, more scalable way of getting information in and out of eBPF programs <br>
Allow data to be shared between different eBPF programs in the kernel, and between kernel and user space applications

![eBPF Maps](/docs/images/getting-started-with-ebpf/ebpf-basics/ebpf-maps.png)

Maps are Key-Value stores, and there are many types of them, each optimized for different purposes

**bpftool**: command-line utility used to manage eBPF programs and maps
- *bpftool prog list*

	![bpftool prog list](/docs/images/getting-started-with-ebpf/ebpf-basics/bpftool-prog-list.png)

	*bpftool prog show id 605*
	*bpftool prog show name buffer_read*
	*bpftool prog show tag ...*	

Show available features: *bpftool feature | less*