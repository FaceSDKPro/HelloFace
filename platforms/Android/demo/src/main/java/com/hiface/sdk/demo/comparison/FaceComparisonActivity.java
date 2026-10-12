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
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.demo.R;
import com.hiface.sdk.demo.ui.DemoErrorUi;

/** 从系统相册选择两张图片并执行离线人脸 1:1 对比。 */
public final class FaceComparisonActivity extends AppCompatActivity {
    private TextView compareButton;
    private TextView similarityValue;
    @Nullable
    private Float similarity;
    @Nullable
    private String comparisonError;
    private FacePhotoSlot leftSlot;
    private FacePhotoSlot rightSlot;
    private FacePhotoPicker photoPicker;
    private HiFaceSdk hiFaceSdk;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_face_comparison);

        bindViews();
        bindActions();
    }

    private void bindViews() {
        leftSlot = new FacePhotoSlot(findViewById(R.id.leftPhoto), R.string.face_compare_photo_1);
        rightSlot = new FacePhotoSlot(findViewById(R.id.rightPhoto), R.string.face_compare_photo_2);
        compareButton = findViewById(R.id.compareButton);
        similarityValue = findViewById(R.id.similarityValue);
        photoPicker = new FacePhotoPicker(this);
        hiFaceSdk = HiFaceSdk.builder(this)
                .lifecycleOwner(this)
                .build();
    }

    /** 集中绑定页面事件。 */
    private void bindActions() {
        findViewById(R.id.backButton).setOnClickListener(view -> finish());
        leftSlot.setOnClickListener(view -> pickPhoto(leftSlot));
        rightSlot.setOnClickListener(view -> pickPhoto(rightSlot));
        compareButton.setOnClickListener(view -> compareFaces());
        updateControls();
    }

    /** 选择并预处理指定图片位的照片。 */
    private void pickPhoto(@NonNull FacePhotoSlot slot) {
        photoPicker.pick(new FacePhotoPicker.Callback() {
            @Override
            public void onPicked(@NonNull Bitmap bitmap) {
                extractPhotoFeature(slot, bitmap);
            }

            @Override
            public void onError(@NonNull Throwable error) {
                showPhotoPickerError(slot, getString(R.string.face_compare_photo_failed));
            }
        });
    }

    /** SDK 管理图片推理和主线程回调，页面销毁时自动取消请求。 */
    private void extractPhotoFeature(@NonNull FacePhotoSlot slot, @NonNull Bitmap bitmap) {
        slot.setBitmap(bitmap);
        similarity = null;
        comparisonError = null;
        updateControls();
        hiFaceSdk.capture().fromBitmap(bitmap, result -> {
            // 已更换照片或释放槽位时，旧图片的成功结果和错误都不再更新界面。
            if (slot.bitmap != bitmap) return;
            if (result.isSuccess()) {
                slot.setCapture(result.requireValue());
            } else {
                slot.extracting = false;
                slot.error = DemoErrorUi.messageFor(this, result.requireError());
            }
            updateControls();
        });
    }

    /** 两侧特征就绪后直接比较 String，不再读取 Bitmap 或重复运行模型。 */
    private void compareFaces() {
        String faceFeature1 = leftSlot.feature;
        String faceFeature2 = rightSlot.feature;
        if (faceFeature1 == null || faceFeature2 == null) return;
        showComparisonResult(hiFaceSdk.verification().compare(faceFeature1, faceFeature2));
    }

    /** 分数常驻页面，不把相似度解释成身份概率或自行添加通过阈值。 */
    private void showComparisonResult(@NonNull HiFaceResult<Float> result) {
        similarity = result.isSuccess() ? result.requireValue() : null;
        comparisonError = result.isFailure() ? DemoErrorUi.messageFor(this, result.requireError()) : null;
        updateControls();
    }

    /** 新照片读取失败时保留槽位原有图片和特征，只在对应位置显示原因。 */
    private void showPhotoPickerError(@NonNull FacePhotoSlot slot, @NonNull String message) {
        slot.error = message;
        updateControls();
    }

    /** 特征未就绪时禁用比较；照片处理过程中仍可更换任意一张照片。 */
    private void updateControls() {
        boolean ready = leftSlot.feature != null && rightSlot.feature != null;
        compareButton.setEnabled(ready);
        leftSlot.render();
        rightSlot.render();
        renderResult();
    }

    /** 未得到分数时不占页面空间；换图立即清除上一次结果。 */
    private void renderResult() {
        if (similarity != null) {
            similarityValue.setVisibility(View.VISIBLE);
            similarityValue.setTextColor(ContextCompat.getColor(this, R.color.content_accent));
            similarityValue.setText(getString(R.string.face_compare_result, similarity * 100f));
        } else if (comparisonError != null) {
            similarityValue.setVisibility(View.VISIBLE);
            similarityValue.setTextColor(ContextCompat.getColor(this, R.color.content_error));
            similarityValue.setText(comparisonError);
        } else {
            similarityValue.setVisibility(View.GONE);
        }
    }

    @Override
    protected void onDestroy() {
        photoPicker.close();
        leftSlot.close();
        rightSlot.close();
        super.onDestroy();
    }

    /** 管理单个图片槽位及其 Bitmap 生命周期，仅供本页面使用。 */
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
        private boolean extracting;
        @Nullable
        private String error;

        FacePhotoSlot(@NonNull View root, @StringRes int labelText) {
            container = root.findViewById(R.id.photoContainer);
            container.setClipToOutline(true); // 方法从 API 21 可用，XML 属性仅在较新系统生效。
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

        void setBitmap(@NonNull Bitmap value) {
            recycleBitmap();
            bitmap = value;
            feature = null;
            error = null;
            extracting = true;
            imageView.setImageBitmap(value);
            placeholder.setVisibility(View.GONE);
        }

        void render() {
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

        /** 只取一次独立 Bitmap，释放原图；槽位保存裁剪图和 String，不长期持有整份结果。 */
        void setCapture(@NonNull FaceCaptureResult capture) {
            setBitmap(capture.getAlignedFace());
            feature = capture.getFeature();
            extracting = false;
        }

        @Override
        public void close() {
            feature = null;
            extracting = false;
            imageView.setImageDrawable(null);
            recycleBitmap();
        }

        private void recycleBitmap() {
            Bitmap value = bitmap;
            bitmap = null;
            if (value != null && !value.isRecycled()) {
                value.recycle();
            }
        }
    }
}
