package com.hiface.sdk.demo.search;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;
import android.widget.ImageView;
import android.graphics.Bitmap;
import com.hiface.sdk.demo.storage.FacePhotoStore;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.recyclerview.widget.DiffUtil;
import androidx.recyclerview.widget.ListAdapter;
import androidx.recyclerview.widget.RecyclerView;

import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.search.FaceSearchStore.Person;

import java.util.List;

/**
 * Display metadata and an optional private face thumbnail; keep image loading outside list diffs.
 *
 * 列表展示资料和可选私有头像；图片异步读取，不参与列表差分。
 */
final class FaceSearchLibraryAdapter extends ListAdapter<Person, FaceSearchLibraryAdapter.Holder> {
    interface OnDeleteListener {
        void onDelete(String faceId);
    }

    static final DiffUtil.ItemCallback<Person> DIFF = new DiffUtil.ItemCallback<Person>() {
        /**
         * faceId identifies the record; changing its group does not create a different list item.
         *
         * faceId 是记录身份，分组变化仍视为同一列表项。
         */
        @Override
        public boolean areItemsTheSame(@NonNull Person oldPerson, @NonNull Person newPerson) {
            return oldPerson.id.equals(newPerson.id);
        }

        /**
         * For the same ID, compare only visible metadata; features and update timestamps do not trigger
         * redraws.
         *
         * 同一 ID 只比较界面展示的元数据，特征和更新时间不参与列表重绘。
         */
        @Override
        public boolean areContentsTheSame(@NonNull Person oldPerson, @NonNull Person newPerson) {
            return oldPerson.group.equals(newPerson.group) && oldPerson.tag.equals(newPerson.tag);
        }
    };

    interface OnEditListener { void onEdit(Person person); }
    private OnEditListener onEdit;
    private OnDeleteListener onDelete;
    private PendingCommit pendingCommit;

    /**
     * Allow Diff computation to finish, but release Activity and page data from commit closures after
     * cancellation.
     *
     * Diff 工作可自然完成，但取消后不再通过 commit 闭包保留 Activity 和整页数据。
     */
    static final class PendingCommit implements Runnable {
        private Runnable action;
        PendingCommit(Runnable action) { this.action = action; }
        void cancel() { action = null; }
        @Override public void run() {
            Runnable value = action;
            action = null;
            if (value != null) value.run();
        }
    }

    @Override
    public void submitList(@Nullable List<Person> list) {
        submitList(list, null);
    }

    @Override
    public void submitList(@Nullable List<Person> list, @Nullable Runnable commitCallback) {
        if (pendingCommit != null) pendingCommit.cancel();
        pendingCommit = commitCallback == null ? null : new PendingCommit(commitCallback);
        super.submitList(list, pendingCommit);
    }

    void release() {
        onDelete = null;
        onEdit = null;
        submitList(null);
    }

    private void delete(String faceId) {
        if (onDelete != null) onDelete.onDelete(faceId);
    }

    /**
     * Defer scroll-state restoration while the list is empty until the first asynchronous page arrives.
     *
     * 空列表期间暂缓恢复滚动状态，等待异步首批数据到达。
     */
    FaceSearchLibraryAdapter(OnDeleteListener onDelete) { this(onDelete, null); }

    FaceSearchLibraryAdapter(OnDeleteListener onDelete, OnEditListener onEdit) {
        super(DIFF);
        this.onEdit = onEdit;
        this.onDelete = onDelete;
        setStateRestorationPolicy(RecyclerView.Adapter.StateRestorationPolicy.PREVENT_WHEN_EMPTY);
    }

    @NonNull
    @Override
    public Holder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_search_person, parent, false);
        return new Holder(view, this::delete, person -> { if (onEdit != null) onEdit.onEdit(person); });
    }

    @Override
    public void onBindViewHolder(@NonNull Holder holder, int position) {
        holder.bind(getItem(position));
    }

    @Override public void onViewRecycled(@NonNull Holder holder) {
        holder.releasePhoto();
        super.onViewRecycled(holder);
    }

    static final class Holder extends RecyclerView.ViewHolder {
        private final TextView id;
        private final TextView group;
        private final View delete;
        private final ImageView photo;
        private FacePhotoStore.Request photoRequest;
        private Bitmap photoBitmap;
        private String faceId;
        private Person person;

        Holder(View view, OnDeleteListener onDelete, OnEditListener onEdit) {
            super(view);
            id = view.findViewById(R.id.personId);
            group = view.findViewById(R.id.personGroup);
            delete = view.findViewById(R.id.personDelete);
            photo = view.findViewById(R.id.personPhoto);
            // 使用当前绑定的资料，不捕获旧列表位置；修改后只刷新元数据。
            view.findViewById(R.id.personEdit).setOnClickListener(v -> onEdit.onEdit(person));
            // A recycled card must delete its current ID, not a captured old ID or list position.
            // 复用卡片后必须删除当前 ID，不能捕获旧 ID 或列表位置。
            delete.setOnClickListener(v -> onDelete.onDelete(faceId));
        }

        /**
         * Refresh the recycled row's ID, metadata, and deletion target; show the ungrouped label for an empty
         * group.
         *
         * 刷新复用行的 ID、元数据和删除目标，空分组显示未分组文案。
         */
        void bind(Person person) {
            releasePhoto();
            this.person = person;
            faceId = person.id;
            final String requestedId = faceId;
            photoRequest = FacePhotoStore.loadAsync(itemView.getContext(), requestedId, bitmap -> {
                if (!requestedId.equals(faceId)) { if (bitmap != null) bitmap.recycle(); return; }
                photoRequest = null;
                photoBitmap = bitmap;
                if (bitmap != null) {
                    photo.setImageTintList(null);
                    photo.setPadding(0, 0, 0, 0);
                    photo.setScaleType(ImageView.ScaleType.CENTER_CROP);
                    photo.setImageBitmap(bitmap);
                }
            });
            id.setText(person.id);
            String name = person.group.isEmpty()
                    ? itemView.getContext().getString(R.string.search_ungrouped) : person.group;
            String metadata = itemView.getContext().getString(R.string.search_ui_person_group, name);
            if (!person.tag.isEmpty()) {
                metadata += itemView.getContext().getString(R.string.search_ui_person_tag, person.tag);
            }
            group.setText(metadata);
            delete.setContentDescription(itemView.getContext()
                    .getString(R.string.search_ui_delete_accessibility, person.id));
        }

        void releasePhoto() {
            if (photoRequest != null) { photoRequest.cancel(); photoRequest = null; }
            photo.setImageResource(R.drawable.ic_search_person);
            photo.setImageTintList(android.content.res.ColorStateList.valueOf(
                    androidx.core.content.ContextCompat.getColor(itemView.getContext(), R.color.search_accent)));
            int padding = (int) (11 * itemView.getResources().getDisplayMetrics().density + 0.5f);
            photo.setPadding(padding, padding, padding, padding);
            if (photoBitmap != null) { photoBitmap.recycle(); photoBitmap = null; }
        }
    }
}
