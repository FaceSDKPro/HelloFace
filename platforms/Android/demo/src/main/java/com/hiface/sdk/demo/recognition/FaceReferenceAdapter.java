package com.hiface.sdk.demo.recognition;

import android.content.res.ColorStateList;
import android.graphics.Bitmap;
import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.core.content.ContextCompat;
import androidx.recyclerview.widget.RecyclerView;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.storage.FacePhotoStore;
import java.util.ArrayList;
import java.util.List;

/** Only visible references decode private thumbnails; recycled holders cancel pending image work. */
public final class FaceReferenceAdapter extends RecyclerView.Adapter<FaceReferenceAdapter.Holder> {
    public interface Selection {
        void select(String faceId);
    }

    private final List<String> ids = new ArrayList<>();
    private final Selection selection;
    private final Selection deletion;
    // Track created holders so closing the page can release portraits beyond currently visible rows.
    private final List<Holder> holders = new ArrayList<>();
    private boolean closed;

    public FaceReferenceAdapter(Selection selection, Selection deletion) {
        this.selection = selection;
        this.deletion = deletion;
    }

    /** Preserve the scroll position and decoded portraits on camera return; captures may replace a photo. */
    public void update(List<String> next, boolean reloadPhotos) {
        if (!reloadPhotos && ids.equals(next)) {
            return;
        }
        ids.clear();
        ids.addAll(next);
        notifyDataSetChanged();
    }

    @NonNull
    @Override
    public Holder onCreateViewHolder(@NonNull ViewGroup parent, int type) {
        Holder holder = new Holder(
                LayoutInflater.from(parent.getContext()).inflate(R.layout.item_recognition_reference, parent, false));
        holders.add(holder);
        return holder;
    }

    @Override
    public void onBindViewHolder(@NonNull Holder holder, int position) {
        holder.clear();
        String id = ids.get(position);
        ReferenceGestureGate gesture = new ReferenceGestureGate();
        int touchSlop = ViewConfiguration.get(holder.itemView.getContext()).getScaledTouchSlop();
        holder.name.setText(id);
        holder.itemView.setContentDescription(
                holder.itemView.getContext().getString(R.string.recognition_verify_person, id));
        holder.itemView.setOnTouchListener((view, event) -> {
            gesture.onTouch(event.getActionMasked(), event.getX(), event.getY(), touchSlop);
            return false;
        });
        holder.itemView.setOnClickListener(view -> {
            if (gesture.canActivate()) {
                selection.select(id);
            }
        });
        holder.itemView.setOnLongClickListener(view -> {
            if (!gesture.canActivate()) {
                return false;
            }
            gesture.consumeLongPress();
            deletion.select(id);
            return true;
        });
        int padding = Math.round(16 * holder.photo.getResources().getDisplayMetrics().density);
        holder.photo.setPadding(padding, padding, padding, padding);
        holder.photo.setImageResource(R.drawable.ic_search_person);
        holder.photo.setImageTintList(
                ColorStateList.valueOf(ContextCompat.getColor(holder.photo.getContext(), R.color.content_accent)));
        holder.request = FacePhotoStore.REFERENCE.loadAsync(holder.photo.getContext(), id, image -> {
            if (closed) {
                if (image != null) {
                    image.recycle();
                }
                return;
            }
            holder.bitmap = image;
            if (image != null) {
                holder.photo.setPadding(0, 0, 0, 0);
                holder.photo.setImageTintList(null);
                holder.photo.setImageBitmap(image);
            }
        });
    }

    @Override
    public int getItemCount() {
        return ids.size();
    }

    @Override
    public void onViewRecycled(@NonNull Holder holder) {
        holder.clear();
    }

    public void close() {
        closed = true;
        for (Holder holder : holders) {
            holder.clear();
        }
        holders.clear();
    }

    static final class Holder extends RecyclerView.ViewHolder {
        final ImageView photo;
        final TextView name;
        FacePhotoStore.Request request;
        Bitmap bitmap;

        Holder(View view) {
            super(view);
            photo = view.findViewById(R.id.referenceAvatar);
            photo.setClipToOutline(true);
            name = view.findViewById(R.id.referenceFaceId);
        }

        // Cancel this binding's load before recycling its Bitmap and reusing the holder for another ID.
        void clear() {
            if (request != null) {
                request.cancel();
                request = null;
            }
            itemView.setOnTouchListener(null);
            itemView.setOnClickListener(null);
            itemView.setOnLongClickListener(null);
            photo.setImageDrawable(null);
            if (bitmap != null) {
                bitmap.recycle();
                bitmap = null;
            }
        }
    }
}
