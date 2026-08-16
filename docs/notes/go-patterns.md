#### **Pattern: Resource Management with `defer`**

**Definition:** `defer` schedules a function call to run immediately before the surrounding function returns.

- **Execution Order:** Last-In-First-Out (LIFO). The last `defer` written is the first to execute.
    
- **Evaluation:** Arguments are evaluated **immediately** when the `defer` line is reached, but the function body is executed later.
    
- **Safety:** Ensures cleanup happens even if the function panics or returns early due to an error.
    

**Best Practice:** Always check for errors **before** deferring a cleanup task.

```
f, err := os.Open("file.txt")
if err != nil {
    return err // Don't defer if opening failed
}
defer f.Close()
```

#### **Pattern: Thread Pinning with `runtime.LockOSThread`**

**Definition:** Pins the calling goroutine to its current operating system thread.

- **Context:** Essential when interacting with OS features that are thread-local (like Linux Namespaces).
    
- **The Go Scheduler Issue:** Normally, the Go runtime moves goroutines between OS threads to balance load. This is dangerous if a thread has specific "state" (like being inside a custom namespace).
    
- **Lifecycle:** The thread remains locked until `UnlockOSThread` is called or the goroutine exits. If a goroutine exits while locked, the runtime terminates the underlying OS thread to prevent "state leakage."