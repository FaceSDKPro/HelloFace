package com.hiface.sdk.demo.search;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.text.InputType;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.StringRes;
import androidx.appcompat.app.AlertDialog;

import com.google.android.material.button.MaterialButton;
import com.google.android.material.button.MaterialButtonToggleGroup;
import com.google.android.material.switchmaterial.SwitchMaterial;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.search.FaceSearchSessionConfig;
import com.hiface.sdk.search.FaceSearchMode;

/** 设置只编辑草稿，校验通过并点击“应用”后才更新运行中的搜索。 */
final class SearchSettingsDialog {
    /** 默认匹配成功后立即开始下一轮；只影响成功后的下一轮，不控制相机帧率。 */
    static final int DEMO_SUCCESS_INTERVAL_MILLIS = 0;

    static FaceSearchSessionConfig demoDefaultConfig() {
        return FaceSearchSessionConfig.builder()
                .searchIntervalMillis(DEMO_SUCCESS_INTERVAL_MILLIS)
                .build();
    }

    interface OnApplyListener {
        void onApply(FaceSearchSessionConfig config);
    }

    private final Context context;
    private final FaceSearchSessionConfig current;
    private MaterialButtonToggleGroup modes;
    private MaterialButton single;
    private MaterialButton multi;
    private MaterialButton more;
    private TextView modeHint;
    private TextView liveHint;
    private SwitchMaterial live;
    private LinearLayout advanced;
    private SearchUi.Input maxFaces;
    private SearchUi.Input group;
    private SearchUi.Input threshold;
    private SearchUi.Input interval;
    private SearchUi.Input timeout;

    /** 以当前运行配置创建独立草稿弹窗，应用成功后才通知搜索页面。 */
    static AlertDialog show(Context owner, FaceSearchSessionConfig current, OnApplyListener listener) {
        return new SearchSettingsDialog(owner, current).showDialog(listener);
    }

    private SearchSettingsDialog(Context owner, FaceSearchSessionConfig current) {
        context = SearchUi.theme(owner);
        this.current = current;
    }

    /** 组装设置表单并接管应用/重置按钮，校验失败时保持弹窗打开。 */
    private AlertDialog showDialog(OnApplyListener listener) {
        LinearLayout form = SearchUi.form(context);
        addModeSettings(form);
        addScopeSettings(form);
        addSearchParameters(form);
        modes.addOnButtonCheckedListener((buttons, id, checked) -> {
            if (checked) {
                updateMode(id == multi.getId());
            }
        });
        modes.check(current.getMode() == FaceSearchMode.MULTI_FACE ? multi.getId() : single.getId());
        live.setChecked(current.needsLiveness());
        maxFaces.set(String.valueOf(current.getMaxFacesPerFrame()));

        maxFaces.edit.setNextFocusForwardId(group.edit.getId());
        group.edit.setNextFocusForwardId(threshold.edit.getId());
        threshold.edit.setImeOptions(EditorInfo.IME_ACTION_DONE);
        interval.edit.setNextFocusForwardId(timeout.edit.getId());
        timeout.edit.setImeOptions(EditorInfo.IME_ACTION_DONE);
        SearchUi.FormScrollView scroll = SearchUi.scroll(form);
        AlertDialog dialog = SearchUi.formDialog(context)
                .setTitle(R.string.search_settings)
                .setView(scroll)
                .setNeutralButton(R.string.search_ui_reset, null)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.search_apply, null)
                .create();
        dialog.setOnShowListener(ignored -> {
            dialog.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(v -> resetDraft());
            dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
                FaceSearchSessionConfig next = readConfig();
                if (next != null) {
                    listener.onApply(next);
                    dialog.dismiss();
                }
            });
        });
        SearchUi.showFormDialog(dialog, scroll);
        return dialog;
    }

    /** 创建单人/多人模式、单帧活体开关和多人采样上限控件。 */
    private void addModeSettings(LinearLayout form) {
        SearchUi.section(form, R.string.search_ui_mode_section);
        modes = new MaterialButtonToggleGroup(context);
        modes.setSingleSelection(true);
        modes.setSelectionRequired(true);
        single = modeButton(R.string.search_ui_single_mode);
        multi = modeButton(R.string.search_ui_multi_mode);
        modes.addView(single, new LinearLayout.LayoutParams(0, SearchUi.dp(context, 48), 1));
        modes.addView(multi, new LinearLayout.LayoutParams(0, SearchUi.dp(context, 48), 1));
        form.addView(modes);
        modeHint = SearchUi.text(context, R.string.search_ui_single_hint, 12, false);
        modeHint.setPadding(0, SearchUi.dp(context, 10), 0, 0);
        form.addView(modeHint);

        live = new SwitchMaterial(context);
        live.setText(R.string.search_ui_live_switch);
        live.setTextSize(14);
        live.setMinHeight(SearchUi.dp(context, 48));
        form.addView(live);
        liveHint = SearchUi.text(context, R.string.search_ui_live_help, 12, false);
        form.addView(liveHint);
        maxFaces = SearchUi.field(form, R.string.search_ui_max_label, "3",
                R.string.search_ui_max_help, InputType.TYPE_CLASS_NUMBER);
    }

    /** 编辑本 Demo 支持的 group 条件；留空表示搜索所有分组。 */
    private void addScopeSettings(LinearLayout form) {
        SearchUi.section(form, R.string.search_ui_scope_section);
        form.addView(SearchUi.text(context, R.string.search_ui_scope_help, 12, false));
        group = SearchUi.field(form, R.string.search_ui_group_label, current.getGroup(),
                0, InputType.TYPE_CLASS_TEXT);
        group.box.setPlaceholderText(context.getString(R.string.search_ui_group_example));
    }

    /** 展示相似度门槛，将成功间隔与单轮超时收进可展开的高级参数区。 */
    private void addSearchParameters(LinearLayout form) {
        SearchUi.section(form, R.string.search_ui_parameters);
        threshold = SearchUi.field(form, R.string.search_ui_threshold_label,
                String.valueOf(current.getThreshold()), R.string.search_ui_threshold_help,
                InputType.TYPE_CLASS_NUMBER | InputType.TYPE_NUMBER_FLAG_DECIMAL);
        more = new MaterialButton(context);
        more.setBackgroundTintList(ColorStateList.valueOf(Color.TRANSPARENT));
        more.setTextColor(context.getColor(R.color.search_accent));
        more.setStateListAnimator(null);
        more.setElevation(0);
        more.setIconTint(ColorStateList.valueOf(context.getColor(R.color.search_accent)));
        more.setText(R.string.search_ui_more_parameters);
        more.setTextSize(12);
        more.setAllCaps(false);
        more.setMinHeight(SearchUi.dp(context, 48));
        more.setIconResource(R.drawable.ic_search_chevron);
        more.setIconSize(SearchUi.dp(context, 18));
        more.setIconGravity(MaterialButton.ICON_GRAVITY_TEXT_END);
        form.addView(more);

        advanced = new LinearLayout(context);
        advanced.setOrientation(LinearLayout.VERTICAL);
        advanced.setVisibility(View.GONE);
        form.addView(advanced);
        interval = SearchUi.field(advanced, R.string.search_ui_interval_label,
                String.valueOf(current.getSearchIntervalMillis()),
                R.string.search_ui_interval_help, InputType.TYPE_CLASS_NUMBER);
        timeout = SearchUi.field(advanced, R.string.search_ui_timeout_label,
                String.valueOf(current.getSearchTimeoutMillis()),
                R.string.search_ui_timeout_help, InputType.TYPE_CLASS_NUMBER);
        interval.box.setSuffixText(context.getString(R.string.search_ui_millis));
        timeout.box.setSuffixText(context.getString(R.string.search_ui_millis));
        more.setOnClickListener(v -> showAdvanced(advanced.getVisibility() != View.VISIBLE));
    }

    /** 切到多人模式时关闭并禁用活体，切回单人时默认开启；采样上限仅在多人模式显示。 */
    private void updateMode(boolean many) {
        live.setChecked(!many);
        live.setEnabled(!many);
        live.setAlpha(many ? .45f : 1f);
        liveHint.setText(many ? R.string.search_ui_live_disabled : R.string.search_ui_live_help);
        modeHint.setText(many ? R.string.search_ui_multi_hint : R.string.search_ui_single_hint);
        maxFaces.box.setVisibility(many ? View.VISIBLE : View.GONE);
    }

    /** 切换高级参数区的可见性，保留已经填写的草稿值。 */
    private void showAdvanced(boolean visible) {
        advanced.setVisibility(visible ? View.VISIBLE : View.GONE);
        more.setSelected(visible);
    }

    /** 恢复 Demo 参数；成功间隔默认为 0，匹配成功后立即开始下一轮。 */
    private void resetDraft() {
        FaceSearchSessionConfig defaults = demoDefaultConfig();
        modes.check(single.getId());
        live.setChecked(defaults.needsLiveness());
        group.set("");
        threshold.set(String.valueOf(defaults.getThreshold()));
        interval.set(String.valueOf(defaults.getSearchIntervalMillis()));
        timeout.set(String.valueOf(defaults.getSearchTimeoutMillis()));
        maxFaces.set(String.valueOf(defaults.getMaxFacesPerFrame()));
    }

    /** 返回 null 时保留弹窗，并在对应字段显示错误。 */
    private FaceSearchSessionConfig readConfig() {
        float score;
        try {
            score = Float.parseFloat(threshold.value());
        } catch (NumberFormatException error) {
            threshold.error(R.string.search_ui_error_threshold);
            return null;
        }
        if (Float.isNaN(score) || score < .75f || score > .85f) {
            threshold.error(R.string.search_ui_error_threshold);
            return null;
        }
        threshold.box.setError(null);
        if (!interval.integerIn(0, 3000, R.string.search_ui_error_interval)
                || !timeout.integerIn(1000, 3000, R.string.search_ui_error_timeout)) {
            showAdvanced(true);
            return null;
        }
        boolean many = modes.getCheckedButtonId() == multi.getId();
        if (many && !maxFaces.integerIn(1, 5, R.string.search_ui_error_max)) {
            return null;
        }
        int limit = current.getMaxFacesPerFrame();
        try {
            int draft = Integer.parseInt(maxFaces.value());
            if (draft >= 1 && draft <= 5) {
                limit = draft;
            }
        } catch (NumberFormatException ignored) {
            // 单人模式下忽略隐藏的未完成输入，保留原有多人采样上限。
        }
        return FaceSearchSessionConfig.builder()
                .mode(many ? FaceSearchMode.MULTI_FACE : FaceSearchMode.SINGLE_FACE)
                .needLiveness(live.isChecked())
                .group(group.value())
                .threshold(score)
                .searchIntervalMillis(Integer.parseInt(interval.value()))
                .searchTimeoutMillis(Integer.parseInt(timeout.value()))
                .maxFacesPerFrame(limit)
                .build();
    }

    /** 创建统一样式且具有独立 View ID 的模式切换按钮。 */
    private MaterialButton modeButton(@StringRes int label) {
        MaterialButton button = new MaterialButton(context);
        button.setId(View.generateViewId());
        button.setText(label);
        button.setAllCaps(false);
        button.setTextSize(13);
        button.setInsetTop(0);
        button.setInsetBottom(0);
        button.setPadding(0, 0, 0, 0);
        button.setCornerRadius(SearchUi.dp(context, 12));
        button.setStrokeWidth(SearchUi.dp(context, 1));
        button.setStrokeColorResource(R.color.search_border);
        button.setBackgroundTintList(context.getColorStateList(R.color.search_mode_fill));
        button.setTextColor(context.getColorStateList(R.color.search_mode_text));
        return button;
    }
}
