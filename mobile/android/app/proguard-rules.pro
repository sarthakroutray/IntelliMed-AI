-keep class ai.onnxruntime.** { *; }

# Google Sign-In v7 uses the Android Credential Manager, and flutter_secure_storage
# reaches the Android Keystore via reflection. Both are reflective JNI/plugin
# entry points that R8 can otherwise strip in release builds.
-keep class androidx.credentials.** { *; }
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# google_mlkit_text_recognition dynamically references the script-specific
# recognizer option classes (Chinese, Devanagari, Japanese, Korean). The app
# only ever constructs the Latin recognizer (see OcrService in lib/cnn_ocr.dart),
# so those classes are legitimately absent from the classpath. Without these
# rules R8 fails the release build outright with "Missing classes detected".
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
