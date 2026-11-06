package com.hiface.sdk.demo.search;

import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.widget.FrameLayout;
import android.text.TextUtils;
import android.text.TextPaint;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextView;
import androidx.annotation.Nullable;
import androidx.appcompat.app.AppCompatActivity;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.capture.FaceImageCapture;
import com.hiface.sdk.common.FaceRequest;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceError;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.comparison.FacePhotoPicker;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.demo.ui.DemoWindowInsets;
import com.hiface.sdk.search.FaceSearchConfig;
import com.hiface.sdk.search.FaceSearchDatabase;
import com.hiface.sdk.search.FaceSearchMatch;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Multi-face image search: the SDK detects, aligns, and extracts features; the Demo queries and
 * displays each face.
 *
 * 图片多人搜索：SDK 负责检测与对齐提特征，Demo 负责逐脸查库和结果展示。
 */
public final class FaceImageSearchActivity extends AppCompatActivity {
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private HiFaceSdk sdk;
    private FacePhotoPicker picker;
    private FaceRequest request;
    private PhotoView photo;
    private TextView status;
    private View loading;
    private View placeholder;
    private View strip;
    private LinearLayout crops;
    private final List<Bitmap> thumbnails = new ArrayList<>();
    private volatile int generation;
    private volatile boolean closed;

    static final class ResultFace {
        final FaceImageCapture face;
        String label;
        boolean matched;
        ResultFace(FaceImageCapture face) { this.face = face; }
    }

    @Override protected void onCreate(@Nullable Bundle state) {
        super.onCreate(state);
        // This screen owns the image-search SDK; destruction closes it and discards pending callbacks.
        // 页面直接持有图片搜索 SDK，销毁时自动关闭并丢弃未执行回调。
        sdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
        picker = new FacePhotoPicker(this, FacePhotoPicker.IMAGE_SEARCH_MAX_DIMENSION_PX);
        setContentView(R.layout.activity_face_image_search);
        DemoWindowInsets.applyToContent(this);
        status = findViewById(R.id.imageSearchStatus);
        crops = findViewById(R.id.imageSearchCrops);
        strip = findViewById(R.id.imageSearchStrip);
        loading = findViewById(R.id.imageSearchLoading);
        placeholder = findViewById(R.id.imageSearchPlaceholder);
        FrameLayout container = findViewById(R.id.imageSearchPhoto);
        container.setClipToOutline(true);
        photo = new PhotoView();
        container.addView(photo, 0, new FrameLayout.LayoutParams(-1, -1));
        container.setOnClickListener(v -> pickPhoto());
        findViewById(R.id.backButton).setOnClickListener(v -> finish());
        findViewById(R.id.imageSearchLibrary).setOnClickListener(v ->
                startActivity(new Intent(this, FaceSearchLibraryActivity.class)));
        findViewById(R.id.imageSearchAlbum).setOnClickListener(v -> pickPhoto());
    }

    private void pickPhoto() {
        picker.pick(new FacePhotoPicker.Callback() {
            @Override public void onPicked(Bitmap bitmap) { load(bitmap); }
            @Override public void onError(Throwable error) { status.setText(R.string.face_compare_photo_failed); }
        });
    }

    /**
     * Changing the image invalidates the previous request immediately; the SDK owns an independent
     * snapshot, so the old Bitmap can be released safely.
     *
     * 换图即让上一轮失效；SDK 持有独立快照，旧 Bitmap 可安全释放。
     */
    private void load(Bitmap bitmap) {
        int token = ++generation;
        if (request != null) request.cancel();
        clearThumbnails();
        photo.setPhoto(bitmap);
        placeholder.setVisibility(View.GONE);
        loading.setVisibility(View.VISIBLE);
        status.setText(R.string.image_search_processing);
        request = sdk.capture().facesFromBitmap(bitmap, extracted -> {
            if (closed || generation != token) return;
            if (extracted.isFailure()) {
                loading.setVisibility(View.GONE);
                status.setText(DemoErrorUi.messageFor(this, extracted.requireError()));
                return;
            }
            List<FaceImageCapture> faces = extracted.requireValue();
            worker.execute(() -> search(faces, token));
        });
    }

    private void search(List<FaceImageCapture> faces, int token) {
        if (closed || generation != token) return;
        List<ResultFace> results = new ArrayList<>();
        if (faces.isEmpty()) {
            main.post(() -> render(token, results, false));
            return;
        }
        HiFaceResult<FaceSearchDatabase> opened = HiFaceSdk.openSearchDatabase(getApplicationContext());
        if (opened.isFailure()) {
            main.post(() -> showError(token, opened.requireError()));
            return;
        }
        try (FaceSearchDatabase db = opened.requireValue()) {
            HiFaceResult<Long> count = db.count(null, null);
            if (count.isFailure()) {
                main.post(() -> showError(token, count.requireError()));
                return;
            }
            for (FaceImageCapture face : faces) {
                if (closed || generation != token) return;
                ResultFace result = new ResultFace(face);
                if (face.getCapture().isFailure()) {
                    result.label = face.getCapture().requireError().getCode() == HiFaceErrorCode.IMAGE_FACE_TOO_SMALL
                            ? getString(R.string.image_search_face_too_small)
                            : DemoErrorUi.messageFor(this, face.getCapture().requireError());
                } else {
                    HiFaceResult<List<FaceSearchMatch>> found = db.search(face.getCapture().requireValue().getFeature(),
                            FaceSearchConfig.defaultConfig());
                    if (found.isFailure()) result.label = DemoErrorUi.messageFor(this, found.requireError());
                    else if (found.requireValue().isEmpty()) result.label = getString(R.string.image_search_unmatched);
                    else {
                        FaceSearchMatch match = found.requireValue().get(0);
                        result.matched = true;
                        result.label = match.getEntry().getFaceId() + "," + String.format(Locale.ROOT, "%.2f", match.getScore());
                    }
                }
                // Build labels once for both the photo and thumbnails; never fabricate IDs or scores for errors.
                // 标签只组装一次，照片和缩略图共用；错误结果不伪造 ID 或分数。
                results.add(result);
            }
            main.post(() -> render(token, results, count.requireValue() == 0));
        }
    }

    private void render(int token, List<ResultFace> results, boolean emptyLibrary) {
        if (closed || generation != token) return;
        loading.setVisibility(View.GONE);
        clearThumbnails();
        strip.setVisibility(results.isEmpty() ? View.GONE : View.VISIBLE);
        photo.faces = results;
        photo.invalidate();
        int matched = 0;
        for (int i = 0; i < results.size(); i++) {
            ResultFace result = results.get(i);
            if (result.matched) matched++;
            addThumbnail(result, i);
        }
        String summary = getString(R.string.image_search_summary, results.size(), matched);
        if (results.isEmpty()) summary = getString(R.string.image_search_no_faces);
        else if (emptyLibrary) summary += "\n" + getString(R.string.image_search_empty_library);
        status.setText(summary);
        photo.setContentDescription(summary);
    }

    private void showError(int token, HiFaceError error) {
        if (closed || generation != token) return;
        loading.setVisibility(View.GONE);
        status.setText(DemoErrorUi.messageFor(this, error));
    }

    private void addThumbnail(ResultFace result, int index) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setGravity(Gravity.CENTER);
        card.setPadding(dp(8), dp(8), dp(8), dp(6));
        card.setBackgroundResource(R.drawable.bg_image_search_card);
        LinearLayout.LayoutParams params = new LinearLayout.LayoutParams(dp(112), -2);
        params.setMarginEnd(dp(10));
        ImageView image = new ImageView(this);
        if (result.face.getCapture().isSuccess()) {
            Bitmap crop = result.face.getCapture().requireValue().getAlignedFace();
            thumbnails.add(crop);
            image.setImageBitmap(crop);
        } else {
            image.setImageResource(R.drawable.ic_search_person);
            image.setImageTintList(android.content.res.ColorStateList.valueOf(getColor(R.color.content_text_secondary)));
        }
        card.addView(image, new LinearLayout.LayoutParams(dp(72), dp(72)));
        TextView label = new TextView(this);
        label.setText(result.label);
        label.setTextSize(11);
        label.setTextColor(getColor(R.color.content_text));
        label.setGravity(Gravity.CENTER);
        label.setMaxLines(2);
        label.setEllipsize(TextUtils.TruncateAt.END);
        label.setPadding(0, dp(6), 0, 0);
        card.addView(label, new LinearLayout.LayoutParams(-1, dp(34)));
        card.setOnClickListener(v -> {
            photo.selected = index;
            photo.invalidate();
            for (int i = 0; i < crops.getChildCount(); i++) crops.getChildAt(i).setBackgroundResource(
                    i == index ? R.drawable.bg_image_search_secondary : R.drawable.bg_image_search_card);
        });
        crops.addView(card, params);
    }

    private int dp(int n) { return Math.round(n * getResources().getDisplayMetrics().density); }
    private void clearThumbnails() {
        crops.removeAllViews();
        strip.setVisibility(View.GONE);
        for (Bitmap bitmap : thumbnails) bitmap.recycle();
        thumbnails.clear();
    }
    @Override protected void onDestroy() {
        closed = true; generation++;
        if (request != null) request.cancel();
        picker.close(); worker.shutdown(); clearThumbnails(); photo.setPhoto(null);
        super.onDestroy();
    }

    private final class PhotoView extends View {
        Bitmap bitmap;
        List<ResultFace> faces = new ArrayList<>();
        int selected = -1;
        final TextPaint paint = new TextPaint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
        PhotoView() { super(FaceImageSearchActivity.this); }
        void setPhoto(Bitmap value) {
            Bitmap previous = bitmap; bitmap = value; faces = new ArrayList<>(); selected = -1;
            invalidate();
            if (previous != null) previous.recycle();
        }
        @Override protected void onDraw(Canvas canvas) {
            super.onDraw(canvas);
            if (bitmap == null) return;
            // Display the image with aspect-fit; boxes and labels share the same scale and padding offsets without
            // changing source coordinates.
            // 图片按 aspect-fit 展示，框和标签共用同一缩放与留白偏移，不改变原图坐标。
            float scale = Math.min(getWidth() / (float) bitmap.getWidth(), getHeight() / (float) bitmap.getHeight());
            float x = (getWidth() - bitmap.getWidth() * scale) / 2;
            float y = (getHeight() - bitmap.getHeight() * scale) / 2;
            paint.setStyle(Paint.Style.FILL); paint.setColor(Color.WHITE);
            canvas.drawBitmap(bitmap, null, new RectF(x, y, x + bitmap.getWidth()*scale, y + bitmap.getHeight()*scale), paint);
            for (int i = 0; i < faces.size(); i++) {
                ResultFace result = faces.get(i); FaceImageCapture f = result.face;
                RectF box = new RectF(x+f.getX()*scale, y+f.getY()*scale,
                        x+(f.getX()+f.getWidth())*scale, y+(f.getY()+f.getHeight())*scale);
                paint.setColor(result.matched ? Color.rgb(32, 185, 70) : Color.rgb(207, 126, 20));
                paint.setStyle(Paint.Style.STROKE); paint.setStrokeWidth(dp(i == selected ? 4 : 2));
                canvas.drawRect(box, paint);
                paint.setStyle(Paint.Style.FILL); paint.setTextSize(dp(10));
                float maxLabelWidth = Math.min(getWidth() - dp(12), Math.max(box.width(), dp(96)));
                String label = TextUtils.ellipsize(result.label, paint, maxLabelWidth, TextUtils.TruncateAt.END).toString();
                float labelX = Math.max(dp(4), Math.min(box.left, getWidth()-paint.measureText(label)-dp(8)));
                float labelY = Math.max(dp(16), box.top);
                paint.setColor(0xCC111111);
                canvas.drawRect(labelX, labelY-dp(16), labelX+paint.measureText(label)+dp(8), labelY, paint);
                paint.setColor(Color.WHITE); canvas.drawText(label, labelX+dp(4), labelY-dp(4), paint);
            }
        }
    }
}
