package com.hiface.sdk.demo.ui;

import com.hiface.sdk.flow.FaceAction;
import java.util.HashSet;
import java.util.List;
import org.junit.Test;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

public final class FaceFlowUiTest {
    @Test
    public void everySupportedActionCountIsDistinctAndWithinSdkActions() {
        for (int count = 0; count <= FaceAction.values().length; count++) {
            List<FaceAction> actions = FaceFlowUi.randomActions(count);
            assertEquals(count, actions.size());
            assertEquals(count, new HashSet<>(actions).size());
            for (FaceAction action : actions) {
                assertNotNull(action);
            }
        }
    }

    @Test
    public void eachChallengeOwnsItsActionList() {
        List<FaceAction> actions = FaceFlowUi.randomActions(FaceAction.values().length);
        actions.clear();
        assertEquals(FaceAction.values().length,
                FaceFlowUi.randomActions(FaceAction.values().length).size());
    }

    @Test
    public void invalidCountsAreRejected() {
        for (int count : new int[]{-1, FaceAction.values().length + 1}) {
            try {
                FaceFlowUi.randomActions(count);
                fail("Expected invalid action count");
            } catch (IllegalArgumentException expected) {
                assertTrue(expected.getMessage().startsWith("Action count is outside"));
            }
        }
    }
}
