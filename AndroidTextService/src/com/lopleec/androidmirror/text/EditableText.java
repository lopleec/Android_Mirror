package com.lopleec.androidmirror.text;

/** Cursor offsets come from Android in UTF-16 units. Invalid/unknown ranges must not replace text. */
final class EditableText {
    static String insert(String old, int start, int end, String text) {
        if (old.isEmpty()) { start = 0; end = 0; }
        if (start < 0 || end < 0 || start > old.length() || end > old.length()) return null;
        int low = Math.min(start, end), high = Math.max(start, end);
        if (!boundary(old, low) || !boundary(old, high)) return null;
        return old.substring(0, low) + text + old.substring(high);
    }
    private static boolean boundary(String text, int offset) {
        return offset == 0 || offset == text.length() || !Character.isHighSurrogate(text.charAt(offset - 1))
                || !Character.isLowSurrogate(text.charAt(offset));
    }
}
