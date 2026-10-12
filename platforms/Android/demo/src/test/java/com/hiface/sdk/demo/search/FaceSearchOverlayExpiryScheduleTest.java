package com.hiface.sdk.demo.search;

import org.junit.Test;

import static org.junit.Assert.*;

public final class FaceSearchOverlayExpiryScheduleTest {
    @Test public void extendedDeadlinesKeepOneEarlyCheck() {
        FaceSearchOverlayExpirySchedule schedule = new FaceSearchOverlayExpirySchedule();
        assertFalse(schedule.update(0));
        assertTrue(schedule.update(1200));
        for (int index = 0; index < 10_000; index++) assertFalse(schedule.update(1200 + index));
        schedule.reset();
        assertTrue(schedule.update(11_200));
    }

    @Test public void earlierDeadlinePreemptsAndEmptyContentCancels() {
        FaceSearchOverlayExpirySchedule schedule = new FaceSearchOverlayExpirySchedule();
        assertTrue(schedule.update(1200));
        assertTrue(schedule.update(1000));
        assertFalse(schedule.update(1100));
        assertTrue(schedule.update(0));
        assertFalse(schedule.update(0));
        assertTrue(schedule.update(1300));
        schedule.reset();
        assertTrue(schedule.update(1300));
    }
}
