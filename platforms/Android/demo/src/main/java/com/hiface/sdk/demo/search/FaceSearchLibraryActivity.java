package com.hiface.sdk.demo.search;

import android.os.Bundle;
import android.text.Editable;
import android.text.TextWatcher;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.EditText;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.NonNull;
import androidx.annotation.StringRes;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.PopupMenu;
import androidx.recyclerview.widget.LinearLayoutManager;
import androidx.recyclerview.widget.RecyclerView;

import com.google.android.material.textfield.TextInputLayout;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.search.FaceSearchStore.Person;

import java.util.Collections;
import java.util.List;

/** 人脸库管理示例：滚动加载、精确查询、批量导入和删除；数据库操作由 Store 串行执行。 */
public final class FaceSearchLibraryActivity extends AppCompatActivity {
    private static final int LOAD_SIZE = 100;
    private static final int PREFETCH_REMAINING = 10;

    private FaceSearchStore store;
    private FaceSearchStore.Request<?> pendingTask;
    private RecyclerView rows;
    private LinearLayoutManager layoutManager;
    private FaceSearchLibraryAdapter adapter;
    private TextView status;
    private EditText query;
    private View empty;
    private TextView emptyTitle;
    private TextView emptyHint;
    private View menuButton;
    private TextInputLayout queryField;
    private AlertDialog dialog;
    private HiFaceSdk imageSdk;
    private int generation;
    private int nextOffset;
    private long total;
    private boolean canLoadMore;
    private boolean lookupMode;
    private boolean loading;

    /** 创建页面独享的数据库连接和列表，实际读取在页面可见时触发。 */
    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        setContentView(R.layout.activity_face_search_library);
        bindViews();
        bindActions();
    }

    /** 绑定列表和空态控件，删除操作交回页面确认后执行。 */
    private void bindViews() {
        rows = findViewById(R.id.libraryRows);
        status = findViewById(R.id.libraryStatus);
        query = findViewById(R.id.libraryQuery);
        empty = findViewById(R.id.libraryEmpty);
        emptyTitle = findViewById(R.id.libraryEmptyTitle);
        emptyHint = findViewById(R.id.libraryEmptyHint);
        menuButton = findViewById(R.id.libraryMenu);
        queryField = findViewById(R.id.libraryQueryField);

        layoutManager = new LinearLayoutManager(this);
        rows.setLayoutManager(layoutManager);
        rows.setHasFixedSize(true);
        rows.setItemAnimator(null);
        adapter = new FaceSearchLibraryAdapter(this::confirmDelete);
        rows.setAdapter(adapter);
    }

    /** 绑定功能菜单、精确 ID 查询和距列表末尾 10 条时的下一批预加载。 */
    private void bindActions() {
        findViewById(R.id.libraryBack).setOnClickListener(v -> finish());
        menuButton.setOnClickListener(this::showMenu);
        queryField.setEndIconOnClickListener(v -> lookup());
        query.setOnEditorActionListener((v, action, event) -> {
            if (action == EditorInfo.IME_ACTION_SEARCH) {
                lookup();
                return true;
            }
            return false;
        });
        query.addTextChangedListener(new TextWatcher() {
            @Override public void beforeTextChanged(CharSequence s, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence s, int start, int before, int count) {
                if (s.toString().trim().isEmpty() && lookupMode) {
                    loadFirstPage();
                }
            }

            @Override public void afterTextChanged(Editable value) {}
        });
        rows.addOnScrollListener(new RecyclerView.OnScrollListener() {
            @Override
            public void onScrolled(@NonNull RecyclerView view, int dx, int dy) {
                if (dy > 0) {
                    loadMoreIfNeeded();
                }
            }
        });
    }

    /** 右上角只保留一个菜单入口，集中展示刷新和两种批量导入示例。 */
    private void showMenu(View anchor) {
        PopupMenu popup = new PopupMenu(this, anchor);
        popup.inflate(R.menu.face_search_library);
        popup.setOnMenuItemClickListener(item -> {
            if (item.getItemId() == R.id.libraryMenuRefresh) {
                resetSearch();
                return true;
            }
            if (item.getItemId() == R.id.libraryMenuImportFeatures) {
                confirmImport(false);
                return true;
            }
            if (item.getItemId() == R.id.libraryMenuImportImages) {
                confirmImport(true);
                return true;
            }
            return false;
        });
        popup.show();
    }

    /** 导入通过 saveFeatures 新增或覆盖，开始前明确说明数量、覆盖行为及图片网络要求。 */
    private void confirmImport(boolean images) {
        if (loading) {
            return;
        }
        if (dialog != null) {
            dialog.dismiss();
        }
        dialog = SearchUi.dialog(this)
                .setTitle(images ? R.string.search_ui_import_images
                        : R.string.search_ui_import_features)
                .setMessage(images ? R.string.search_ui_import_images_message
                        : R.string.search_ui_import_features_message)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.search_ui_import_start,
                        (d, which) -> startImport(images))
                .create();
        dialog.show();
    }

    /** 页面只选择导入类型；JSON 解析、下载、特征提取和分批写库都由 Store 串行完成。 */
    private void startImport(boolean images) {
        if (store == null) return;
        cancelTask();
        int requestId = ++generation;
        int count = images ? FaceSearchStore.IMAGE_DEMO_COUNT
                : FaceSearchStore.FEATURE_DEMO_COUNT;
        loading = true;
        status.setText(getString(R.string.search_ui_import_progress, 0, count));
        updateActions();
        FaceSearchStore.ProgressCallback progress = value -> {
            if (requestId == generation) {
                status.setText(getString(R.string.search_ui_import_progress,
                        value.processed, value.total));
            }
        };
        FaceSearchStore.Callback<FaceSearchStore.ImportSummary> complete = result -> {
            if (requestId != generation) {
                return;
            }
            pendingTask = null;
            loading = false;
            releaseImageSdk();
            if (result.isFailure()) {
                showError(result.requireError(), false);
                Toast.makeText(this, R.string.search_ui_import_failed, Toast.LENGTH_LONG).show();
                return;
            }
            FaceSearchStore.ImportSummary summary = result.requireValue();
            Toast.makeText(this, getString(R.string.search_ui_import_done,
                    summary.imported, summary.failed), Toast.LENGTH_LONG).show();
            resetSearch();
        };
        if (images) {
            if (imageSdk == null) {
                imageSdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
            }
            pendingTask = store.importImageDemo(imageSdk.capture(), progress, complete);
        } else {
            pendingTask = store.importFeatureDemo(progress, complete);
        }
    }

    /** 清除精确查询并只触发一次首批读取。 */
    private void resetSearch() {
        lookupMode = false;
        query.setText("");
        loadFirstPage();
    }

    /** 清空旧列表并从前 100 条重新读取。 */
    private void loadFirstPage() {
        if (store == null) return;
        cancelTask();
        generation++;
        lookupMode = false;
        loading = false;
        total = 0;
        nextOffset = 0;
        canLoadMore = false;
        adapter.submitList(Collections.emptyList());
        rows.scrollToPosition(0);
        loadPage(0);
    }

    /** 第 90、190、290…条进入可见范围时，提前读取下一批 100 条。 */
    private void loadMoreIfNeeded() {
        if (loading || lookupMode || adapter.getItemCount() == 0 || !canLoadMore) {
            return;
        }
        int lastVisible = layoutManager.findLastVisibleItemPosition();
        if (lastVisible >= adapter.getItemCount() - PREFETCH_REMAINING - 1) {
            loadPage(nextOffset);
        }
    }

    /** 从指定数据库偏移读取一批；首次替换列表，后续按 ID 合并。 */
    private void loadPage(int start) {
        int requestId = generation;
        showLoading(start == 0);
        pendingTask = store.loadPage(start, LOAD_SIZE, result -> {
            if (requestId != generation) {
                return;
            }
            pendingTask = null;
            if (result.isFailure()) {
                showError(result.requireError(), start == 0);
                return;
            }
            showPage(requestId, start, result.requireValue());
        });
    }

    /** 合并 Adapter 已提交的快照，不再维护第二份列表；Diff 完成后才允许继续翻页。 */
    private void showPage(int requestId, int start, FaceSearchStore.Page loaded) {
        List<Person> merged = start == 0 ? loaded.people
                : FaceSearchStore.mergePeople(adapter.getCurrentList(), loaded.people);
        adapter.submitList(merged, () -> {
            if (requestId != generation) {
                return;
            }
            loading = false;
            nextOffset = start + loaded.people.size();
            canLoadMore = !loaded.people.isEmpty() && nextOffset < loaded.total;
            total = start > 0 && loaded.people.isEmpty()
                    ? merged.size() : Math.max(loaded.total, merged.size());
            empty.setVisibility(View.GONE);
            status.setText(getString(R.string.search_ui_total, total));
            if (total == 0) {
                showEmpty(R.string.search_ui_empty_library, R.string.search_ui_empty_library_hint);
            }
            updateActions();
            loadMoreIfNeeded();
        });
    }

    /** 按完整 faceId 精确查询；空输入返回滚动列表，NOT_FOUND 显示空结果。 */
    private void lookup() {
        if (loading || store == null) {
            return;
        }
        String faceId = query.getText().toString().trim();
        if (faceId.isEmpty()) {
            loadFirstPage();
            return;
        }
        InputMethodManager keyboard = (InputMethodManager) getSystemService(INPUT_METHOD_SERVICE);
        if (keyboard != null) {
            keyboard.hideSoftInputFromWindow(query.getWindowToken(), 0);
        }
        cancelTask();
        int requestId = ++generation;
        lookupMode = true;
        showLoading(true);
        pendingTask = store.find(faceId, result -> {
            if (requestId != generation) {
                return;
            }
            pendingTask = null;
            if (result.isFailure() && result.requireError().getCode() != HiFaceErrorCode.NOT_FOUND) {
                showError(result.requireError(), true);
                return;
            }
            List<Person> found = result.isSuccess()
                    ? Collections.singletonList(result.requireValue()) : Collections.emptyList();
            showLookup(requestId, found);
        });
    }

    /** 提交单条 ID 查询结果，缺失记录使用专门的未找到提示。 */
    private void showLookup(int requestId, List<Person> found) {
        adapter.submitList(found, () -> {
            if (requestId != generation) {
                return;
            }
            loading = false;
            nextOffset = 0;
            canLoadMore = false;
            rows.scrollToPosition(0);
            empty.setVisibility(View.GONE);
            status.setText(R.string.search_ui_lookup_result);
            if (found.isEmpty()) {
                showEmpty(R.string.search_ui_not_found, R.string.search_ui_not_found_hint);
            }
            updateActions();
        });
    }

    /** 显示待删除的具体 ID，用户确认后才提交删除操作。 */
    private void confirmDelete(String faceId) {
        if (loading) {
            return;
        }
        if (dialog != null) {
            dialog.dismiss();
        }
        AlertDialog confirmation = SearchUi.dialog(this)
                .setTitle(R.string.search_ui_delete_title)
                .setMessage(getString(R.string.search_ui_delete_message, faceId))
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.search_ui_delete_confirm, (d, which) -> delete(faceId))
                .create();
        confirmation.setOnShowListener(d -> confirmation.getButton(AlertDialog.BUTTON_POSITIVE)
                .setTextColor(getColor(R.color.search_error_color)));
        dialog = confirmation;
        confirmation.show();
    }

    /** 串行删除指定 ID，成功后刷新当前查询或从首批重新加载。 */
    private void delete(String faceId) {
        if (store == null) return;
        cancelTask();
        int requestId = ++generation;
        loading = true;
        updateActions();
        pendingTask = store.delete(faceId, result -> {
            if (requestId != generation) {
                return;
            }
            pendingTask = null;
            loading = false;
            if (result.isFailure()) {
                showError(result.requireError(), adapter.getItemCount() == 0);
            } else if (lookupMode) {
                lookup();
            } else {
                loadFirstPage();
            }
        });
    }

    /** 首次读取显示加载提示；追加读取保留当前条数，避免列表滚动时文案闪烁。 */
    private void showLoading(boolean initial) {
        loading = true;
        if (initial) {
            status.setText(R.string.search_ui_loading);
        }
        updateActions();
    }

    /** 使未完成页面任务及其回调失效；已经提交的数据库批次保持有效。 */
    private void cancelTask() {
        if (pendingTask != null) {
            pendingTask.cancel();
            pendingTask = null;
        }
    }

    /** 图片导入结束或页面离开后释放模型；下次导入独立创建，不长期占用搜索页的内存。 */
    private void releaseImageSdk() {
        if (imageSdk != null) {
            imageSdk.close();
            imageSdk = null;
        }
    }

    /** 查询和功能菜单只在没有数据库任务运行时可用。 */
    private void updateActions() {
        menuButton.setEnabled(!loading);
        queryField.setEnabled(!loading);
    }

    /** 显示空列表的标题与引导，区分空库、未找到和读取失败。 */
    private void showEmpty(@StringRes int title, @StringRes int hint) {
        empty.setVisibility(View.VISIBLE);
        emptyTitle.setText(title);
        emptyHint.setText(hint);
    }

    /** 首批失败显示空态；追加失败保留已加载内容，用户可点击刷新重试。 */
    private void showError(HiFaceError error, boolean initial) {
        loading = false;
        canLoadMore = false;
        status.setText(SearchUi.errorText(error));
        if (initial) {
            nextOffset = 0;
            adapter.submitList(Collections.emptyList());
            showEmpty(R.string.search_ui_library_error, R.string.search_ui_library_error_hint);
        }
        updateActions();
    }

    /** 返回页面时从首批重新读取，展示其他页面产生的数据库变化。 */
    @Override
    protected void onStart() {
        super.onStart();
        if (store == null) store = new FaceSearchStore(this);
        if (query.getText().toString().trim().isEmpty()) {
            loadFirstPage();
        } else {
            lookup();
        }
    }

    /** 后台或离开时取消任务并关闭管理连接，返回后重新读取已提交的数据。 */
    @Override
    protected void onStop() {
        generation++;
        cancelTask();
        releaseImageSdk();
        if (store != null) store.close();
        store = null;
        if (dialog != null) {
            dialog.dismiss();
            dialog = null;
        }
        loading = false;
        canLoadMore = false;
        // 下一次 onStart 会重新查询；后台不保留列表数据和异步 Diff 的页面闭包。
        adapter.submitList(null);
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        rows.clearOnScrollListeners();
        rows.setAdapter(null);
        adapter.release();
        super.onDestroy();
    }

}
