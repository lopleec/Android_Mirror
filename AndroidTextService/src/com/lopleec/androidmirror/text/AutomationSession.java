package com.lopleec.androidmirror.text;

import android.app.UiAutomation;
import android.os.Build;
import android.os.HandlerThread;
import android.os.Looper;
import java.lang.reflect.Constructor;

/** Shared shell-only lifecycle. Existing accessibility services remain active. */
final class AutomationSession implements AutoCloseable {
    private final HandlerThread thread;
    private UiAutomation automation;
    AutomationSession(String threadName) throws Exception {
        if (Build.VERSION.SDK_INT < 24) throw new UnsupportedOperationException();
        if (Looper.getMainLooper() == null) Looper.prepareMainLooper();
        thread = new HandlerThread(threadName); thread.start();
        try {
            Class<?> type = Class.forName("android.app.IUiAutomationConnection");
            Object connection = Class.forName("android.app.UiAutomationConnection").getDeclaredConstructor().newInstance();
            Constructor<UiAutomation> constructor = UiAutomation.class.getDeclaredConstructor(Looper.class, type);
            automation = constructor.newInstance(thread.getLooper(), connection);
            UiAutomation.class.getMethod("connect", int.class).invoke(automation, UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES);
        } catch (Exception error) { close(); throw error; }
    }
    UiAutomation get() { return automation; }
    void refresh() { if (Build.VERSION.SDK_INT >= 34) automation.clearCache(); }
    @Override public void close() {
        if (automation != null) {
            try { UiAutomation.class.getMethod("disconnect").invoke(automation); } catch (Exception ignored) { }
            automation = null;
        }
        thread.quitSafely();
    }
}
