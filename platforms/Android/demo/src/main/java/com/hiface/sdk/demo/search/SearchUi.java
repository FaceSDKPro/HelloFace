package com.hiface.sdk.demo.search;

import android.content.Context;
import android.graphics.Typeface;
import android.view.View;
import android.view.ViewGroup;
import android.widget.LinearLayout;
import android.widget.TextView;

import androidx.annotation.StringRes;
import androidx.appcompat.view.ContextThemeWrapper;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.textfield.TextInputLayout;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.demo.R;

/** 搜索页面共用的主题、表单控件和错误文案。 */
final class SearchUi {
    private SearchUi() {}

    static int dp(Context context, float value) {
        return Math.round(value * context.getResources().getDisplayMetrics().density);
    }

    /** 为搜索相关弹窗和表单使用统一主题，不改变宿主 Activity 的主题。 */
    static Context theme(Context context) {
        return new ContextThemeWrapper(context, R.style.Theme_HiFace_Search);
    }

    static MaterialAlertDialogBuilder dialog(Context context) {
        return new MaterialAlertDialogBuilder(theme(context));
    }

    /** 创建可滚动弹窗的纵向表单容器，初始焦点留在容器而非输入框。 */
    static LinearLayout form(Context context) {
        LinearLayout form = new LinearLayout(context);
        form.setOrientation(LinearLayout.VERTICAL);
        // 打开长表单时停在标题处，避免自动滚到第一个输入框。
        form.setFocusableInTouchMode(true);
        form.setFocusable(true);
        form.setPadding(dp(context, 24), dp(context, 8), dp(context, 24), dp(context, 8));
        return form;
    }

    static TextView text(Context context, @StringRes int label, int size, boolean heading) {
        TextView view = new TextView(context);
        view.setText(label);
        view.setTextSize(size);
        view.setTextColor(context.getColor(heading ? android.R.color.white : R.color.text_on_dark_secondary));
        if (heading) {
            view.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        }
        view.setLineSpacing(dp(context, 2), 1f);
        return view;
    }

    static void section(LinearLayout form, @StringRes int label) {
        Context context = form.getContext();
        TextView view = text(context, label, 14, true);
        LinearLayout.LayoutParams params = rowParams();
        params.topMargin = dp(context, 18);
        params.bottomMargin = dp(context, 8);
        form.addView(view, params);
    }

    /** 创建带标签、可选帮助文本和独立 View ID 的单行输入框，并加入表单。 */
    static Input field(LinearLayout form, @StringRes int label, String value,
            @StringRes int helper, int type) {
        Context context = form.getContext();
        TextInputLayout box = new TextInputLayout(context);
        box.setHint(context.getString(label));
        box.setBoxBackgroundMode(TextInputLayout.BOX_BACKGROUND_OUTLINE);
        if (helper != 0) {
            box.setHelperText(context.getString(helper));
        }
        TextInputEditText edit = new TextInputEditText(box.getContext());
        edit.setId(View.generateViewId());
        edit.setSingleLine(true);
        edit.setTextSize(14);
        edit.setTextColor(context.getColor(android.R.color.white));
        edit.setInputType(type);
        edit.setText(value);
        edit.setMinHeight(dp(context, 52));
        box.addView(edit, rowParams());
        LinearLayout.LayoutParams params = rowParams();
        params.topMargin = dp(context, 12);
        form.addView(box, params);
        return new Input(box, edit);
    }

    private static LinearLayout.LayoutParams rowParams() {
        return new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    /** 只重试可暂时失败的有效会话；BUSY/CLOSED 启动拒绝不能通过原会话 resume 恢复。 */
    static boolean canResumeSearch(HiFaceError error) {
        switch (error.getCode()) {
            case NOT_READY:
            case PROCESSING_FAILED:
            case DATABASE_ERROR:
                return true;
            default:
                return false;
        }
    }

    /** 将技术错误码映射到搜索页面文案，未单独处理的错误使用通用提示。 */
    @StringRes
    static int errorText(HiFaceError error) {
        switch (error.getCode()) {
            case MODEL_LOAD_FAILED:
                return R.string.search_ui_error_models;
            case DATABASE_ERROR:
                return R.string.search_ui_error_database;
            case BUSY:
                return R.string.search_ui_error_busy;
            case CLOSED:
                return R.string.search_ui_error_closed;
            default:
                return R.string.search_ui_error_general;
        }
    }

    static final class Input {
        final TextInputLayout box;
        final TextInputEditText edit;

        Input(TextInputLayout box, TextInputEditText edit) {
            this.box = box;
            this.edit = edit;
        }

        /** 读取并去除两端空白，统一表单空输入的处理方式。 */
        String value() {
            return edit.getText() == null ? "" : edit.getText().toString().trim();
        }

        /** 回填草稿值时清除上一次校验错误。 */
        void set(String value) {
            edit.setText(value);
            box.setError(null);
        }

        /** 显示字段错误并定位焦点，返回 false 便于串联表单校验。 */
        boolean error(@StringRes int label) {
            box.setError(box.getContext().getString(label));
            edit.requestFocus();
            return false;
        }

        /** 校验闭区间内的整数，空输入、溢出和越界都定位到当前字段。 */
        boolean integerIn(int min, int max, @StringRes int error) {
            try {
                int value = Integer.parseInt(value());
                if (value >= min && value <= max) {
                    box.setError(null);
                    return true;
                }
            } catch (NumberFormatException ignored) {
                // 空输入或超出整数范围同样显示字段错误。
            }
            return error(error);
        }
    }
}
