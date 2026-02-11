package qml;

import java.lang.foreign.*;
import java.lang.invoke.*;
import java.util.concurrent.Callable;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.CountDownLatch;

/**
 * Centralized Qt thread dispatch.
 *
 * All Qt GUI operations must run on the Qt main thread. This class provides
 * invoke() (fire-and-forget) and invokeSync() (blocking with return value)
 * that post tasks to the Qt event loop via a C++ trampoline.
 */
public class QtThread {

    private static final ConcurrentHashMap<Long, Runnable> tasks = new ConcurrentHashMap<>();
    private static final AtomicLong nextId = new AtomicLong(1);

    private static final Linker LINKER = Linker.nativeLinker();
    private static final SymbolLookup LOOKUP = SymbolLookup.loaderLookup();

    private static final MethodHandle INVOKE_ON_QT;
    private static final MethodHandle INVOKE_ON_QT_SYNC;
    private static final MemorySegment UPCALL_STUB;

    static {
        // Downcalls to C++
        INVOKE_ON_QT = downcall("cuirq_invoke_on_qt_thread",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));
        INVOKE_ON_QT_SYNC = downcall("cuirq_invoke_on_qt_thread_sync",
                FunctionDescriptor.ofVoid(ValueLayout.ADDRESS, ValueLayout.JAVA_LONG));

        // Persistent upcall stub: void(*)(long)
        try {
            MethodHandle executeHandle = MethodHandles.lookup().findStatic(
                    QtThread.class, "executeTask",
                    MethodType.methodType(void.class, long.class));

            FunctionDescriptor callbackDescriptor = FunctionDescriptor.ofVoid(ValueLayout.JAVA_LONG);
            UPCALL_STUB = LINKER.upcallStub(executeHandle, callbackDescriptor, Arena.ofAuto());
        } catch (Throwable t) {
            throw new ExceptionInInitializerError(t);
        }
    }

    private static MethodHandle downcall(String name, FunctionDescriptor descriptor) {
        MemorySegment symbol = LOOKUP.find(name)
                .orElseThrow(() -> new UnsatisfiedLinkError("Symbol not found: " + name));
        return LINKER.downcallHandle(symbol, descriptor);
    }

    /**
     * Called from C++ on the Qt main thread via the upcall stub.
     */
    private static void executeTask(long id) {
        Runnable task = tasks.remove(id);
        if (task != null) {
            task.run();
        }
    }

    /**
     * Post a task to the Qt main thread (fire-and-forget).
     */
    public static void invoke(Runnable task) {
        long id = nextId.getAndIncrement();
        tasks.put(id, task);
        try {
            INVOKE_ON_QT.invokeExact(UPCALL_STUB, id);
        } catch (Throwable t) {
            tasks.remove(id);
            throw new RuntimeException("Failed to invoke on Qt thread", t);
        }
    }

    /**
     * Post a task to the Qt main thread and block until it completes.
     * Returns the result of the callable. Propagates exceptions.
     */
    public static <T> T invokeSync(Callable<T> task) {
        AtomicReference<T> result = new AtomicReference<>();
        AtomicReference<Throwable> error = new AtomicReference<>();
        CountDownLatch latch = new CountDownLatch(1);

        long id = nextId.getAndIncrement();
        tasks.put(id, () -> {
            try {
                result.set(task.call());
            } catch (Throwable t) {
                error.set(t);
            } finally {
                latch.countDown();
            }
        });

        try {
            INVOKE_ON_QT_SYNC.invokeExact(UPCALL_STUB, id);
        } catch (Throwable t) {
            tasks.remove(id);
            throw new RuntimeException("Failed to invoke sync on Qt thread", t);
        }

        try {
            latch.await();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new RuntimeException("Interrupted waiting for Qt thread", e);
        }

        if (error.get() != null) {
            throw new RuntimeException("Exception on Qt thread", error.get());
        }
        return result.get();
    }
}
