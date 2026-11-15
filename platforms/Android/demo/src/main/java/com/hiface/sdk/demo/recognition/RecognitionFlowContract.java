package com.hiface.sdk.demo.recognition;

import android.content.Intent;
import com.hiface.sdk.flow.FaceAction;
import java.util.ArrayList;
import java.util.List;

/** Demo navigation payloads contain IDs/options and display results; features stay in the store. */
public final class RecognitionFlowContract {
    public static final String FACE_ID = "recognition.faceId";
    public static final String ACTIONS = "recognition.actions";
    public static final String SILENT = "recognition.silent";
    public static final String TITLE = "recognition.result.title";
    public static final String MESSAGE = "recognition.result.message";
    public static final String STATUS = "recognition.result.status";
    public static final String PASSED = "passed", REJECTED = "rejected", ERROR = "error", CANCELED = "canceled";

    private RecognitionFlowContract() {}

    public static Intent configure(Intent intent, List<FaceAction> actions, boolean silent) {
        String[] names = new String[actions.size()];
        for (int i = 0; i < actions.size(); i++) names[i] = actions.get(i).name();
        return intent.putExtra(ACTIONS, names).putExtra(SILENT, silent);
    }

    public static List<FaceAction> actions(Intent intent) {
        String[] names = intent.getStringArrayExtra(ACTIONS);
        List<FaceAction> actions = new ArrayList<>();
        if (names == null) return actions;
        if (names.length > 4) throw new IllegalArgumentException("At most four actions are supported");
        for (String name : names) {
            if (name == null) throw new IllegalArgumentException("An action name is missing");
            actions.add(FaceAction.valueOf(name));
        }
        return actions;
    }

    public static Intent result(String title, String message, String status) {
        return new Intent().putExtra(TITLE, title).putExtra(MESSAGE, message).putExtra(STATUS, status);
    }
}
