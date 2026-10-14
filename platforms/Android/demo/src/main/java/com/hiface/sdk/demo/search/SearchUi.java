package com.hiface.sdk.demo.search;

import android.content.Context;
import android.content.res.ColorStateList;
import android.graphics.Rect;
import android.graphics.Typeface;
import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowManager;
import android.view.ViewTreeObserver;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.StringRes;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.view.ContextThemeWrapper;

import com.google.android.material.button.MaterialButton;
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

    static MaterialAlertDialogBuilder formDialog(Context context) {
        return dialog(context).setBackgroundInsetStart(0).setBackgroundInsetEnd(0);
    }

    static FormScrollView scroll(LinearLayout form) {
        FormScrollView scroll = new FormScrollView(form.getContext());
        scroll.setClipToPadding(false);
        scroll.addView(form);
        return scroll;
    }

    /** 窄屏两侧留 12dp；键盘弹出后只收缩表单，标题和操作按钮保留。 */
    static void showFormDialog(AlertDialog dialog, FormScrollView scroll) {
        dialog.show();
        Window window = dialog.getWindow();
        if (window == null) return;
        Context context = scroll.getContext();
        window.clearFlags(WindowManager.LayoutParams.FLAG_ALT_FOCUSABLE_IM
                | WindowManager.LayoutParams.FLAG_FULLSCREEN);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE
                | WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN);
        int availableWidth = dp(context, context.getResources().getConfiguration().screenWidthDp);
        window.setLayout(Math.min(dp(context, 560), availableWidth - dp(context, 24)),
                ViewGroup.LayoutParams.WRAP_CONTENT);
        for (int which : new int[] {AlertDialog.BUTTON_POSITIVE, AlertDialog.BUTTON_NEGATIVE,
                AlertDialog.BUTTON_NEUTRAL}) {
            Button button = dialog.getButton(which);
            if (button == null) continue;
            button.setAllCaps(false);
            if (which == AlertDialog.BUTTON_POSITIVE) {
                button.setBackgroundTintList(ColorStateList.valueOf(
                        context.getColor(R.color.search_accent)));
                button.setTextColor(context.getColor(R.color.search_background));
                if (button instanceof MaterialButton) {
                    ((MaterialButton) button).setCornerRadius(dp(context, 12));
                }
            }
        }
        View decor = window.getDecorView();
        Rect visible = new Rect();
        ViewTreeObserver.OnGlobalLayoutListener listener = () -> {
            decor.getWindowVisibleDisplayFrame(visible);
            if (visible.height() <= 0) return;
            int chrome = Math.max(dp(context, 112), decor.getHeight() - scroll.getHeight());
            scroll.setMaximumHeight(Math.max(dp(context, 48), visible.height() - chrome - dp(context, 24)));
            View focus = scroll.findFocus();
            if (focus instanceof TextInputEditText) revealInput(focus);
        };
        decor.getViewTreeObserver().addOnGlobalLayoutListener(listener);
        scroll.addOnAttachStateChangeListener(new View.OnAttachStateChangeListener() {
            @Override public void onViewAttachedToWindow(View view) {}
            @Override public void onViewDetachedFromWindow(View view) {
                if (decor.getViewTreeObserver().isAlive()) {
                    decor.getViewTreeObserver().removeOnGlobalLayoutListener(listener);
                }
                view.removeOnAttachStateChangeListener(this);
            }
        });
    }

    private static void revealInput(View input) {
        input.post(() -> {
            if (!input.isAttachedToWindow() || !input.hasFocus()) return;
            Rect bounds = new Rect();
            input.getDrawingRect(bounds);
            bounds.bottom += dp(input.getContext(), 24);
            input.requestRectangleOnScreen(bounds, true);
        });
    }

    static final class FormScrollView extends ScrollView {
        private int maximumHeight;

        FormScrollView(Context context) {
            super(context);
            maximumHeight = Math.max(dp(context, 48),
                    dp(context, context.getResources().getConfiguration().screenHeightDp - 160));
        }

        void setMaximumHeight(int value) {
            if (maximumHeight == value) return;
            maximumHeight = value;
            requestLayout();
        }

        @Override protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
            int mode = MeasureSpec.getMode(heightMeasureSpec);
            int height = mode == MeasureSpec.UNSPECIFIED ? maximumHeight
                    : Math.min(maximumHeight, MeasureSpec.getSize(heightMeasureSpec));
            super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(height, MeasureSpec.AT_MOST));
        }
    }

    /** 创建可滚动弹窗的纵向表单容器，初始焦点留在容器而非输入框。 */
    static LinearLayout form(Context context) {
        LinearLayout form = new LinearLayout(context);
        form.setOrientation(LinearLayout.VERTICAL);
        // 打开长表单时停在标题处，避免自动滚到第一个输入框。
        form.setFocusableInTouchMode(true);
        form.setPadding(dp(context, 16), dp(context, 4), dp(context, 16), dp(context, 12));
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
        if ((type & InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT) {
            type |= InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS;
        }
        edit.setInputType(type);
        edit.setImeOptions(EditorInfo.IME_ACTION_NEXT);
        edit.setOnFocusChangeListener((view, focused) -> {
            if (focused) revealInput(view);
        });
        edit.setOnEditorActionListener((view, action, event) -> {
            if (action != EditorInfo.IME_ACTION_DONE) return false;
            InputMethodManager keyboard = context.getSystemService(InputMethodManager.class);
            if (keyboard != null) keyboard.hideSoftInputFromWindow(edit.getWindowToken(), 0);
            form.setFocusableInTouchMode(true);
            form.requestFocus();
            return true;
        });
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
            // 高级字段可能仍隐藏，等调用方展开并布局后再定位。
            edit.post(() -> {
                edit.requestFocus();
                revealInput(edit);
            });
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
