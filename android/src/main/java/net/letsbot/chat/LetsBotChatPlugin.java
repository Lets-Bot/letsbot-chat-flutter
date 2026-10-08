package net.letsbot.chat;

import android.Manifest;
import android.app.Activity;
import android.content.ClipData;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.webkit.MimeTypeMap;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;

/**
 * Android side of the LetsBot In-App Chat SDK.
 *
 * <p>Small helpers the hosted chat screen needs and the WebView cannot do alone:
 * the RECORD_AUDIO runtime permission (voice notes), a system file chooser for
 * {@code <input type=file>}, and the OS version for device metadata.
 */
public final class LetsBotChatPlugin
        implements FlutterPlugin,
                ActivityAware,
                MethodChannel.MethodCallHandler,
                PluginRegistry.RequestPermissionsResultListener,
                PluginRegistry.ActivityResultListener {

    private static final String CHANNEL = "net.letsbot.chat/native";
    private static final int REQUEST_MICROPHONE = 0x4C42;
    private static final int REQUEST_FILES = 0x4C43;

    @Nullable private MethodChannel channel;
    @Nullable private ActivityPluginBinding activityBinding;
    @Nullable private MethodChannel.Result pendingMicrophone;
    @Nullable private MethodChannel.Result pendingFiles;

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        channel = new MethodChannel(binding.getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(this);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        if (channel != null) {
            channel.setMethodCallHandler(null);
            channel = null;
        }
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        binding.addRequestPermissionsResultListener(this);
        binding.addActivityResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) {
            activityBinding.removeRequestPermissionsResultListener(this);
            activityBinding.removeActivityResultListener(this);
            activityBinding = null;
        }
        if (pendingMicrophone != null) {
            pendingMicrophone.success(false);
            pendingMicrophone = null;
        }
        if (pendingFiles != null) {
            pendingFiles.success(new ArrayList<String>());
            pendingFiles = null;
        }
    }

    @Nullable
    private Activity activity() {
        return activityBinding == null ? null : activityBinding.getActivity();
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "osVersion":
                result.success(Build.VERSION.RELEASE);
                break;
            case "requestMicrophone":
                requestMicrophone(result);
                break;
            case "pickFiles":
                List<String> accept = call.argument("accept");
                Boolean multiple = call.argument("multiple");
                pickFiles(accept, multiple != null && multiple, result);
                break;
            default:
                result.notImplemented();
        }
    }

    private void requestMicrophone(@NonNull MethodChannel.Result result) {
        Activity activity = activity();
        if (activity == null) {
            result.success(false);
            return;
        }
        if (activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                == PackageManager.PERMISSION_GRANTED) {
            result.success(true);
            return;
        }
        if (pendingMicrophone != null) {
            result.success(false);
            return;
        }
        pendingMicrophone = result;
        activity.requestPermissions(
                new String[] {Manifest.permission.RECORD_AUDIO}, REQUEST_MICROPHONE);
    }

    @Override
    public boolean onRequestPermissionsResult(
            int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != REQUEST_MICROPHONE) {
            return false;
        }
        boolean granted =
                grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED;
        if (pendingMicrophone != null) {
            pendingMicrophone.success(granted);
            pendingMicrophone = null;
        }
        return true;
    }

    private void pickFiles(
            @Nullable List<String> accept, boolean multiple, @NonNull MethodChannel.Result result) {
        Activity activity = activity();
        if (activity == null || pendingFiles != null) {
            result.success(new ArrayList<String>());
            return;
        }
        String[] mimeTypes = mimeTypesFor(accept);
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        if (mimeTypes.length == 1) {
            intent.setType(mimeTypes[0]);
        } else {
            intent.setType("*/*");
            if (mimeTypes.length > 1) {
                intent.putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes);
            }
        }
        intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, multiple);
        pendingFiles = result;
        try {
            activity.startActivityForResult(Intent.createChooser(intent, null), REQUEST_FILES);
        } catch (RuntimeException e) {
            pendingFiles = null;
            result.success(new ArrayList<String>());
        }
    }

    /** Converts HTML accept values (MIME types, wildcards or ".ext") into MIME types. */
    @NonNull
    private static String[] mimeTypesFor(@Nullable List<String> accept) {
        Set<String> out = new LinkedHashSet<>();
        if (accept != null) {
            for (String raw : accept) {
                if (raw == null) continue;
                for (String part : raw.split(",")) {
                    String value = part.trim().toLowerCase(Locale.ROOT);
                    if (value.isEmpty()) continue;
                    if (value.startsWith(".")) {
                        String mime =
                                MimeTypeMap.getSingleton()
                                        .getMimeTypeFromExtension(value.substring(1));
                        if (mime != null) out.add(mime);
                    } else if (value.contains("/")) {
                        out.add(value);
                    }
                }
            }
        }
        return out.toArray(new String[0]);
    }

    @Override
    public boolean onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        if (requestCode != REQUEST_FILES) {
            return false;
        }
        ArrayList<String> uris = new ArrayList<>();
        if (resultCode == Activity.RESULT_OK && data != null) {
            ClipData clip = data.getClipData();
            if (clip != null) {
                for (int i = 0; i < clip.getItemCount(); i++) {
                    Uri uri = clip.getItemAt(i).getUri();
                    if (uri != null) uris.add(uri.toString());
                }
            } else if (data.getData() != null) {
                uris.add(data.getData().toString());
            }
        }
        if (pendingFiles != null) {
            pendingFiles.success(uris);
            pendingFiles = null;
        }
        return true;
    }
}
