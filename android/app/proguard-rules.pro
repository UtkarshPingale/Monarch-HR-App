# ── Flutter Core Rules ────────────────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**
-keep class io.flutter.embedding.** { *; }

# ── Flutter Plugins ──────────────────────────────────────────────────────────
# Google Play In-App Update
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# Geolocator
-keep class com.baseflow.geolocator.** { *; }
-dontwarn com.baseflow.geolocator.**

# Shared Preferences, URL Launcher, Package Info Plus
-keep class io.flutter.plugins.sharedpreferences.** { *; }
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# ── AndroidX & Window Insets ─────────────────────────────────────────────────
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keep class androidx.core.view.WindowInsetsCompat { *; }
-keep class androidx.core.view.WindowCompat { *; }
-dontwarn androidx.core.view.WindowInsetsControllerCompat

# ── Suppress warning for deprecated Android 15 Edge-to-Edge window color calls in libraries
-dontwarn android.view.Window
