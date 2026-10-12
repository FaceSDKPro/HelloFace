package com.hiface.sdk.demo.search;

import com.hiface.sdk.common.HiFaceErrorCode;
import com.hiface.sdk.common.HiFaceResult;
import com.hiface.sdk.search.FaceSearchDatabase;
import com.hiface.sdk.search.FaceSearchEntry;
import org.junit.Test;

import java.lang.reflect.Proxy;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.function.BiFunction;

import static org.junit.Assert.*;

public final class FaceSearchEnrollmentTest {
    private static FaceSearchDatabase database(BiFunction<String,Object[],Object> call) {
        return (FaceSearchDatabase)Proxy.newProxyInstance(FaceSearchDatabase.class.getClassLoader(),
                new Class<?>[]{FaceSearchDatabase.class},(proxy,method,args) -> call.apply(method.getName(),args));
    }
    @Test public void duplicateIdNeverOverwritesWithoutConfirmation() {
        List<String> calls=new ArrayList<>();
        FaceSearchDatabase db=database((method,args) -> {
            calls.add(method);assertEquals("contains",method);
            assertArrayEquals(new Object[]{"A"},args);
            return HiFaceResult.success(true);
        });
        assertEquals(HiFaceErrorCode.ALREADY_EXISTS,
                FaceSearchStore.saveFeature(db,"A","new-feature","1A",false,new FaceSearchStore.Request<>()).requireError().getCode());
        assertEquals(Arrays.asList("contains"),calls);
    }
    @Test public void newIdIsSavedWithoutASecondPublicWriteChoice() {
        List<String> calls=new ArrayList<>();
        FaceSearchDatabase db=database((method,args) -> {
            calls.add(method);
            if(method.equals("contains"))return HiFaceResult.success(false);
            assertEquals("saveFeature",method);
            assertArrayEquals(new Object[]{"A","new-feature",0L,null,"1A"},args);
            return HiFaceResult.success(true);
        });
        assertTrue(FaceSearchStore.saveFeature(db,"A","new-feature","1A",false,new FaceSearchStore.Request<>()).isSuccess());
        assertEquals(Arrays.asList("contains","saveFeature"),calls);
    }
    @Test public void confirmedOverwritePreservesHiddenTagAndAllowsClearingGroup() {
        String embedding="HF1:"+new String(new char[600]).replace('\0','A');
        FaceSearchEntry previous=new FaceSearchEntry("A",embedding,1,"VIP","1A");
        List<String> calls=new ArrayList<>();
        FaceSearchDatabase db=database((method,args) -> {
            calls.add(method);
            if(method.equals("get")){assertArrayEquals(new Object[]{"A"},args);return HiFaceResult.success(previous);}
            assertEquals("saveFeature",method);
            assertArrayEquals(new Object[]{"A","new-feature",0L,"VIP",""},args);
            return HiFaceResult.success(true);
        });
        assertTrue(FaceSearchStore.saveFeature(db,"A","new-feature","",true,new FaceSearchStore.Request<>()).isSuccess());
        assertEquals(Arrays.asList("get","saveFeature"),calls);
    }
    @Test public void failedReadCannotSilentlyEraseExistingMetadata() {
        HiFaceResult<FaceSearchEntry> failure=HiFaceResult.failure(HiFaceErrorCode.CLOSED,"closed");
        FaceSearchDatabase db=database((method,args) -> {assertEquals("get",method);return failure;});
        assertSame(failure.requireError(),FaceSearchStore.saveFeature(db,"A","new-feature","2B",true,new FaceSearchStore.Request<>()).requireError());
    }
    @Test public void confirmedOverwriteCanRecreateRecordDeletedSinceConfirmation() {
        List<String> calls=new ArrayList<>();
        FaceSearchDatabase db=database((method,args) -> {
            calls.add(method);
            if(method.equals("get"))return HiFaceResult.failure(HiFaceErrorCode.NOT_FOUND,"missing");
            assertEquals("saveFeature",method);
            assertArrayEquals(new Object[]{"A","new-feature",0L,null,"2B"},args);
            return HiFaceResult.success(true);
        });
        assertTrue(FaceSearchStore.saveFeature(db,"A","new-feature","2B",true,new FaceSearchStore.Request<>()).isSuccess());
        assertEquals(Arrays.asList("get","saveFeature"),calls);
    }
    @Test public void cancellationDuringReadPreventsNewAndOverwriteWrites() {
        for (boolean overwrite : new boolean[]{false, true}) {
            FaceSearchStore.Request<?> request = new FaceSearchStore.Request<>();
            List<String> calls = new ArrayList<>();
            FaceSearchDatabase db = database((method, args) -> {
                calls.add(method);
                request.cancel();
                if (method.equals("contains")) return HiFaceResult.success(false);
                assertEquals("get", method);
                return HiFaceResult.failure(HiFaceErrorCode.NOT_FOUND, "missing");
            });
            assertEquals(HiFaceErrorCode.CLOSED,
                    FaceSearchStore.saveFeature(db, "A", "new-feature", "", overwrite, request)
                            .requireError().getCode());
            assertEquals(Arrays.asList(overwrite ? "get" : "contains"), calls);
        }
    }

}
