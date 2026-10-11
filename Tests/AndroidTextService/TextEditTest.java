package com.lopleec.androidmirror.text;

public final class TextEditTest {
    private static void equal(String expected, String actual) {
        if (!java.util.Objects.equals(expected, actual)) throw new AssertionError("Unexpected editor replacement");
    }
    public static void main(String[] args) {
        equal("你好", EditableText.insert("", -1, -1, "你好"));
        equal("ab中文cd", EditableText.insert("abcd", 2, 2, "中文"));
        equal("a中文d", EditableText.insert("abcd", 3, 1, "中文"));
        equal("Hello中文world", EditableText.insert("Hello🙂world", 5, 7, "中文"));
        equal(null, EditableText.insert("Hello🙂world", 6, 6, "中文"));
        equal(null, EditableText.insert("keep", -1, -1, "中文"));
        equal(null, EditableText.insert("keep", 5, 5, "中文"));
        System.out.println("Text editor insertion: 7 checks passed.");
    }
}
