package com.hiface.sdk.demo.comparison;

import android.graphics.Bitmap;
import android.os.Bundle;
import android.view.View;
import android.widget.ImageView;
import android.widget.TextView;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.StringRes;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;
import com.hiface.sdk.HiFaceSdk;
import com.hiface.sdk.capture.FaceCaptureResult;
import com.hiface.sdk.common.FaceRequest;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.ui.DemoErrorUi;
import com.hiface.sdk.demo.ui.DemoWindowInsets;

/**
 * Select two images from the system gallery and compare faces offline, one to one.
 *
 * 从系统相册选择两张图片并执行离线人脸 1:1 对比。
 */
public final class FaceComparisonActivity extends AppCompatActivity {
    private TextView compareButton;
    private TextView similarityValue;
    private FacePhotoSlot leftSlot;
    private FacePhotoSlot rightSlot;
    private FacePhotoPicker photoPicker;
    private HiFaceSdk hiFaceSdk;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_face_comparison);
        DemoWindowInsets.applyToContent(this);

        bindViews();
        bindActions();
    }

    private void bindViews() {
        leftSlot = new FacePhotoSlot(findViewById(R.id.leftPhoto), R.string.face_compare_photo_1);
        rightSlot = new FacePhotoSlot(findViewById(R.id.rightPhoto), R.string.face_compare_photo_2);
        compareButton = findViewById(R.id.compareButton);
        similarityValue = findViewById(R.id.similarityValue);
        photoPicker = new FacePhotoPicker(this);
        // Bind image requests to this screen; destruction closes the SDK and discards pending callbacks.
        // 图片请求绑定当前页面生命周期；页面销毁时关闭 SDK 并丢弃未执行回调。
        hiFaceSdk = HiFaceSdk.builder(this).lifecycleOwner(this).build();
    }

    /**
     * Bind screen events in one place.
     *
     * 集中绑定页面事件。
     */
    private void bindActions() {
        findViewById(R.id.backButton).setOnClickListener(view -> finish());
        leftSlot.setOnClickListener(view -> pickPhoto(leftSlot));
        rightSlot.setOnClickListener(view -> pickPhoto(rightSlot));
        compareButton.setOnClickListener(view -> compareFaces());
        updateControls();
    }

    /**
     * Select and preprocess a photo for the requested image slot.
     *
     * 选择并预处理指定图片位的照片。
     */
    private void pickPhoto(@NonNull FacePhotoSlot slot) {
        photoPicker.pick(new FacePhotoPicker.Callback() {
            @Override
            public void onPicked(@NonNull Bitmap bitmap) {
                extractPhotoFeature(slot, bitmap);
            }

            @Override
            public void onError(@NonNull Throwable error) {
                // A failed replacement keeps the existing preview and any completed comparison.
                slot.cancelExtraction();
                slot.error = getString(R.string.face_compare_photo_failed);
                updateControls();
            }
        });
    }

    /**
     * The SDK manages image inference and main-thread callbacks; requests cancel automatically when the
     * screen is destroyed.
     *
     * SDK 管理图片推理和主线程回调，页面销毁时自动取消请求。
     */
    private void extractPhotoFeature(@NonNull FacePhotoSlot slot, @NonNull Bitmap bitmap) {
        slot.cancelExtraction();
        slot.replaceBitmap(bitmap);
        slot.feature = null;
        slot.error = null;
        similarityValue.setVisibility(View.GONE);
        slot.request = hiFaceSdk.capture().fromBitmap(bitmap, result -> {
            // Ignore both success and error from an old image after the photo is replaced or its slot is released.
            // 已更换照片或释放槽位时，旧图片的成功结果和错误都不再更新界面。
            if (slot.bitmap != bitmap || slot.request == null) {
                return;
            }
            slot.request = null;
            if (result.isSuccess()) {
                slot.setCapture(result.requireValue());
            } else {
                slot.error = DemoErrorUi.messageFor(this, result.requireError());
            }
            updateControls();
        });
        updateControls();
    }

    /**
     * Compare feature Strings directly once both are ready; do not reread Bitmaps or rerun models.
     *
     * 两侧特征就绪后直接比较 String，不再读取 Bitmap 或重复运行模型。
     */
    private void compareFaces() {
        String faceFeature1 = leftSlot.feature;
        String faceFeature2 = rightSlot.feature;
        if (faceFeature1 == null || faceFeature2 == null) {
            return;
        }
        HiFaceResult<Float> result = hiFaceSdk.verification().compare(faceFeature1, faceFeature2);
        similarityValue.setVisibility(View.VISIBLE);
        similarityValue.setTextColor(ContextCompat.getColor(this,
                result.isSuccess() ? R.color.content_accent : R.color.content_error));
        similarityValue.setText(result.isSuccess()
                ? getString(R.string.face_compare_result, result.requireValue() * 100f)
                : DemoErrorUi.messageFor(this, result.requireError()));
    }

    /**
     * Disable comparison until features are ready; either photo can still be replaced during processing.
     *
     * 特征未就绪时禁用比较；照片处理过程中仍可更换任意一张照片。
     */
    private void updateControls() {
        boolean ready = leftSlot.feature != null && rightSlot.feature != null;
        compareButton.setEnabled(ready);
        leftSlot.render();
        rightSlot.render();
    }

    @Override
    protected void onDestroy() {
        photoPicker.close();
        leftSlot.close();
        rightSlot.close();
        super.onDestroy();
    }

    /**
     * Own one image slot and its Bitmap lifecycle, only for this screen.
     *
     * 管理单个图片槽位及其 Bitmap 生命周期，仅供本页面使用。
     */
    private static final class FacePhotoSlot implements AutoCloseable {
        private final View container;
        private final ImageView imageView;
        private final View placeholder;
        private final View loading;
        private final TextView status;
        private final TextView label;
        @Nullable
        private Bitmap bitmap;
        @Nullable
        private String feature;
        // Each slot owns its pending extraction until its main-thread callback or a replacement.
        @Nullable
        private FaceRequest request;
        @Nullable
        private String error;

        FacePhotoSlot(@NonNull View root, @StringRes int labelText) {
            container = root.findViewById(R.id.photoContainer);
            container.setClipToOutline(
                    true); // 方法从 API 21 可用，XML 属性仅在较新系统生效。 / The method is available from API 21; the XML attribute
            // works only on newer systems.
            imageView = root.findViewById(R.id.photoImage);
            placeholder = root.findViewById(R.id.photoPlaceholder);
            loading = root.findViewById(R.id.photoLoading);
            status = root.findViewById(R.id.photoStatus);
            label = root.findViewById(R.id.photoLabel);
            label.setText(labelText);
        }

        void setOnClickListener(@NonNull View.OnClickListener listener) {
            container.setOnClickListener(listener);
        }

        void replaceBitmap(@Nullable Bitmap value) {
            Bitmap previous = bitmap;
            bitmap = value;
            imageView.setImageBitmap(value);
            placeholder.setVisibility(value == null ? View.VISIBLE : View.GONE);
            if (previous != null && previous != value) {
                previous.recycle();
            }
        }

        void cancelExtraction() {
            if (request != null) {
                request.cancel();
            }
            request = null;
        }

        void render() {
            boolean extracting = request != null;
            loading.setVisibility(extracting ? View.VISIBLE : View.GONE);
            int statusText = extracting ? R.string.face_compare_photo_processing
                    : feature != null ? R.string.face_compare_photo_ready : 0;
            status.setVisibility(error != null || statusText != 0 ? View.VISIBLE : View.GONE);
            if (error != null) {
                status.setText(error);
            } else if (statusText != 0) {
                status.setText(statusText);
            }
            status.setTextColor(ContextCompat.getColor(container.getContext(), error != null
                    ? R.color.content_error : feature != null
                                              ? R.color.content_accent : R.color.content_text_secondary));
            CharSequence state = status.getVisibility() == View.VISIBLE
                    ? status.getText() : container.getContext().getString(R.string.face_compare_select_photo);
            container.setContentDescription(label.getText() + " · " + state);
        }

        /**
         * Read the independent Bitmap once and release the original; retain only the cropped image and String,
         * not the entire result.
         *
         * 只取一次独立 Bitmap，释放原图；槽位保存裁剪图和 String，不长期持有整份结果。
         */
        void setCapture(@NonNull FaceCaptureResult capture) {
            replaceBitmap(capture.getAlignedFace());
            feature = capture.getFeature();
        }

        @Override
        public void close() {
            cancelExtraction();
            feature = null;
            replaceBitmap(null);
        }
    }
}
