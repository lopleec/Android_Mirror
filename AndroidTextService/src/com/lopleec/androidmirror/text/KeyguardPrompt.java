package com.lopleec.androidmirror.text;

import android.app.UiAutomation;
import android.accessibilityservice.AccessibilityServiceInfo;
import android.view.accessibility.AccessibilityNodeInfo;

/** Focus an already visible SystemUI password field. Never click controls or read/set text. */
public final class KeyguardPrompt {
    private static boolean usable(AccessibilityNodeInfo node) {
        return node != null && node.isEnabled() && node.isVisibleToUser();
    }
    private static boolean editor(AccessibilityNodeInfo node) {
        if (!usable(node)) return false;
        String id = node.getViewIdResourceName();
        return node.isPassword() || (id != null && (id.endsWith(":id/passwordEntry") || id.endsWith(":id/pinEntry")));
    }
    private static AccessibilityNodeInfo findEditor(AccessibilityNodeInfo node, int depth) {
        if (node == null || depth > 25) return null;
        if (editor(node)) return node;
        for (int i = 0; i < node.getChildCount(); i++) {
            AccessibilityNodeInfo result = findEditor(node.getChild(i), depth + 1);
            if (result != null) return result;
        }
        return null;
    }
    private static String prepare(UiAutomation automation) {
        String result = focus(automation.getRootInActiveWindow());
        if (!"UNAVAILABLE".equals(result)) return result;
        // Some OEMs make the IME the active window. Search trusted keyguard windows only.
        for (android.view.accessibility.AccessibilityWindowInfo window : automation.getWindows()) {
            result = focus(window.getRoot());
            if (!"UNAVAILABLE".equals(result)) return result;
        }
        return "UNAVAILABLE";
    }
    private static String focus(AccessibilityNodeInfo root) {
        if (root == null || root.getPackageName() == null) return "UNAVAILABLE";
        String packageName = root.getPackageName().toString();
        if (!"com.android.systemui".equals(packageName) && !"com.android.keyguard".equals(packageName)) return "UNAVAILABLE";
        AccessibilityNodeInfo field = findEditor(root, 0);
        if (field != null) {
            if (field.isFocused() || field.performAction(AccessibilityNodeInfo.ACTION_FOCUS)) return "READY";
            return "VISIBLE";
        }
        return "UNAVAILABLE";
    }
    public static void main(String[] args) {
        if (args.length != 0) return;
        String result = "UNAVAILABLE";
        try (AutomationSession session = new AutomationSession("MirrorKeyguardPrompt")) {
            UiAutomation automation = session.get();
            AccessibilityServiceInfo info = automation.getServiceInfo();
            info.flags |= AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS | AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS;
            automation.setServiceInfo(info);
            try { automation.waitForIdle(100, 1500); } catch (java.util.concurrent.TimeoutException ignored) {}
            session.refresh();
            result = prepare(automation);
        } catch (Exception ignored) {
            // Do not expose hierarchy, input contents or framework diagnostics.
        }
        System.out.println("MIRROR_KEYGUARD:" + result);
    }
}
