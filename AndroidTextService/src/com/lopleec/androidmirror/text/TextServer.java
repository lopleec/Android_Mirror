package com.lopleec.androidmirror.text;

import android.app.UiAutomation;
import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Bundle;
import android.view.accessibility.AccessibilityNodeInfo;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.nio.charset.StandardCharsets;

/** Temporary shell process: no APK, IME change, clipboard, logging or text persistence. */
public final class TextServer {
    private static boolean insert(UiAutomation automation, String text) {
        AccessibilityNodeInfo root = automation.getRootInActiveWindow();
        if (root == null) return false;
        AccessibilityNodeInfo editor = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT);
        if (editor == null || !editor.isEditable() || editor.isPassword()) return false;
        if (!editor.getActionList().contains(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_TEXT)) return false;
        CharSequence oldText = editor.getText();
        String old = oldText == null || (android.os.Build.VERSION.SDK_INT >= 26 && editor.isShowingHintText()) ? "" : oldText.toString();
        int start = editor.getTextSelectionStart(), end = editor.getTextSelectionEnd();
        String result = EditableText.insert(old, start, end, text);
        if (result == null) return false;
        int low = old.isEmpty() ? 0 : Math.min(start, end);
        Bundle arguments = new Bundle();
        arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, result);
        if (!editor.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)) return false;
        Bundle selection = new Bundle();
        selection.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_START_INT, low + text.length());
        selection.putInt(AccessibilityNodeInfo.ACTION_ARGUMENT_SELECTION_END_INT, low + text.length());
        editor.performAction(AccessibilityNodeInfo.ACTION_SET_SELECTION, selection);
        return true;
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 1 || !args[0].matches("lopleec_text_[a-f0-9]{32}")) return;
        try (AutomationSession session = new AutomationSession("MirrorTextAutomation")) {
            final UiAutomation active = session.get();
            try (LocalServerSocket server = new LocalServerSocket(args[0])) {
                while (true) {
                    try (LocalSocket socket = server.accept()) {
                        int uid = socket.getPeerCredentials().getUid();
                        if (uid != 2000 && uid != 0) continue;
                        DataInputStream input = new DataInputStream(socket.getInputStream());
                        DataOutputStream output = new DataOutputStream(socket.getOutputStream());
                        output.writeInt(0x414d5431); output.flush();
                        while (true) {
                            int length = input.readInt();
                            if (length == 0) return;
                            if (length < 0 || length > 65536) break;
                            byte[] bytes = new byte[length]; input.readFully(bytes);
                            String text = new String(bytes, StandardCharsets.UTF_8);
                            boolean accepted;
                            try {
                                session.refresh();
                                accepted = insert(active, text);
                            }
                            catch (Exception ignored) { accepted = false; }
                            output.writeByte(accepted ? 1 : 0); output.flush();
                        }
                    } catch (java.io.IOException ignored) {
                        // ADB may probe the forwarded port before automation is ready.
                    }
                }
            }
        }
    }
}
