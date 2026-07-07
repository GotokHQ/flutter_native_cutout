# ONNX Runtime Android uses JNI entry points and Java wrapper classes by name.
# Release minification can otherwise strip/obfuscate classes that native code
# resolves during OrtSession.run, causing fatal JNI aborts.
-keep class ai.onnxruntime.** { *; }
-keep class ai.onnxruntime.providers.** { *; }
-dontwarn ai.onnxruntime.**
