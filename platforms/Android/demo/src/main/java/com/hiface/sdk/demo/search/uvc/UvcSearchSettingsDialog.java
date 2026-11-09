package com.hiface.sdk.demo.search.uvc;

import android.content.Context;
import android.os.Bundle;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.EditText;
import androidx.appcompat.app.AlertDialog;
import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.search.FaceSearchSessionConfig;
import com.hiface.sdk.search.InfraredSearchConfig;

/** Edits supported search options with mandatory IR and single-person mode. 中文：不复用普通 RGB 页的模式开关。 */
final class UvcSearchSettingsDialog {
    // Keep API 23 support without java.util.function, which requires API 24.
    interface OnApply { void accept(FaceSearchSessionConfig config); }
    private interface NumberParser<N extends Number> { N parse(String text); }

    private UvcSearchSettingsDialog() {}

    static FaceSearchSessionConfig defaults() { return FaceSearchSessionConfig.builder().build(); }

    /** Rebuild editable options while retaining single-person mode and required IR checks. */
    static FaceSearchSessionConfig withInfrared(FaceSearchSessionConfig options, InfraredSearchConfig ir) {
        return FaceSearchSessionConfig.builder().group(options.getGroup()).threshold(options.getThreshold())
                .searchIntervalMillis(options.getSearchIntervalMillis())
                .searchTimeoutMillis(options.getSearchTimeoutMillis()).infraredLiveness(ir).build();
    }

    static void save(Bundle out, FaceSearchSessionConfig options) {
        out.putString("searchGroup", options.getGroup());
        out.putFloat("searchThreshold", options.getThreshold());
        out.putInt("searchInterval", options.getSearchIntervalMillis());
        out.putInt("searchTimeout", options.getSearchTimeoutMillis());
    }

    static FaceSearchSessionConfig restore(Bundle saved) {
        if (saved == null) return defaults();
        return FaceSearchSessionConfig.builder().group(saved.getString("searchGroup"))
                .threshold(saved.getFloat("searchThreshold", .8f))
                .searchIntervalMillis(saved.getInt("searchInterval", 0))
                .searchTimeoutMillis(saved.getInt("searchTimeout", 3000)).build();
    }

    static AlertDialog show(Context context, FaceSearchSessionConfig current,
            OnApply apply) {
        View form = LayoutInflater.from(context).inflate(R.layout.view_uvc_search_options, null, false);
        EditText group = form.findViewById(R.id.uvcSearchGroup);
        EditText threshold = form.findViewById(R.id.uvcSearchThreshold);
        EditText interval = form.findViewById(R.id.uvcSearchInterval);
        EditText timeout = form.findViewById(R.id.uvcSearchTimeout);
        OnApply fill = config -> {
            group.setText(config.getGroup());
            threshold.setText(String.valueOf(config.getThreshold()));
            interval.setText(String.valueOf(config.getSearchIntervalMillis()));
            timeout.setText(String.valueOf(config.getSearchTimeoutMillis()));
            for (EditText field : new EditText[]{group, threshold, interval, timeout}) field.setError(null);
        };
        fill.accept(current);
        AlertDialog dialog = new MaterialAlertDialogBuilder(context).setTitle(R.string.search_settings)
                .setView(form).setNegativeButton(android.R.string.cancel, null)
                .setNeutralButton(R.string.search_ui_reset, null).setPositiveButton(R.string.search_apply, null).create();
        dialog.setOnShowListener(ignored -> {
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> fill.accept(defaults()));
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                Float score = number(threshold, Float::valueOf, .75f, .85f, R.string.search_ui_error_threshold);
                Integer gap = number(interval, Integer::valueOf, 0, 3000, R.string.search_ui_error_interval);
                Integer budget = number(timeout, Integer::valueOf, 1000, 3000, R.string.search_ui_error_timeout);
                if (score == null || gap == null || budget == null) return;
                apply.accept(FaceSearchSessionConfig.builder().group(group.getText().toString().trim())
                        .threshold(score).searchIntervalMillis(gap).searchTimeoutMillis(budget).build());
                dialog.dismiss();
            });
        });
        dialog.show();
        return dialog;
    }

    /** Shared numeric validation; bounds also reject NaN/infinity, preserving invalid drafts. */
    private static <N extends Number> N number(EditText field, NumberParser<N> parser,
            double min, double max, int error) {
        try {
            N value = parser.parse(field.getText().toString().trim());
            if (value.doubleValue() >= min && value.doubleValue() <= max) {
                field.setError(null);
                return value;
            }
        } catch (NumberFormatException ignored) { /* Keep the draft open for correction. */ }
        field.setError(field.getContext().getString(error));
        return null;
    }
}
