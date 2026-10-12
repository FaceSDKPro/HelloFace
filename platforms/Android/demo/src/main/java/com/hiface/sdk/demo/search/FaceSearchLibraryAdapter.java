package com.hiface.sdk.demo.search;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.TextView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.recyclerview.widget.DiffUtil;
import androidx.recyclerview.widget.ListAdapter;
import androidx.recyclerview.widget.RecyclerView;

import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.search.FaceSearchStore.Person;

import java.util.List;

/** 列表仅展示 ID、分组和标签，按实际显示的字段做局部更新。 */
final class FaceSearchLibraryAdapter extends ListAdapter<Person, FaceSearchLibraryAdapter.Holder> {
    interface OnDeleteListener {
        void onDelete(String faceId);
    }

    static final DiffUtil.ItemCallback<Person> DIFF = new DiffUtil.ItemCallback<Person>() {
        /** faceId 是记录身份，分组变化仍视为同一列表项。 */
        @Override
        public boolean areItemsTheSame(@NonNull Person oldPerson, @NonNull Person newPerson) {
            return oldPerson.id.equals(newPerson.id);
        }

        /** 同一 ID 只比较界面展示的元数据，特征和更新时间不参与列表重绘。 */
        @Override
        public boolean areContentsTheSame(@NonNull Person oldPerson, @NonNull Person newPerson) {
            return oldPerson.group.equals(newPerson.group) && oldPerson.tag.equals(newPerson.tag);
        }
    };

    private OnDeleteListener onDelete;
    private PendingCommit pendingCommit;

    /** Diff 工作可自然完成，但取消后不再通过 commit 闭包保留 Activity 和整页数据。 */
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
        submitList(null);
    }

    private void delete(String faceId) {
        if (onDelete != null) onDelete.onDelete(faceId);
    }

    /** 空列表期间暂缓恢复滚动状态，等待异步首批数据到达。 */
    FaceSearchLibraryAdapter(OnDeleteListener onDelete) {
        super(DIFF);
        this.onDelete = onDelete;
        setStateRestorationPolicy(RecyclerView.Adapter.StateRestorationPolicy.PREVENT_WHEN_EMPTY);
    }

    @NonNull
    @Override
    public Holder onCreateViewHolder(@NonNull ViewGroup parent, int viewType) {
        View view = LayoutInflater.from(parent.getContext())
                .inflate(R.layout.item_search_person, parent, false);
        return new Holder(view, this::delete);
    }

    @Override
    public void onBindViewHolder(@NonNull Holder holder, int position) {
        holder.bind(getItem(position));
    }

    static final class Holder extends RecyclerView.ViewHolder {
        private final TextView id;
        private final TextView group;
        private final View delete;
        private String faceId;

        Holder(View view, OnDeleteListener onDelete) {
            super(view);
            id = view.findViewById(R.id.personId);
            group = view.findViewById(R.id.personGroup);
            delete = view.findViewById(R.id.personDelete);
            // 复用卡片后必须删除当前 ID，不能捕获旧 ID 或列表位置。
            delete.setOnClickListener(v -> onDelete.onDelete(faceId));
        }

        /** 刷新复用行的 ID、元数据和删除目标，空分组显示未分组文案。 */
        void bind(Person person) {
            faceId = person.id;
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
    }
}
