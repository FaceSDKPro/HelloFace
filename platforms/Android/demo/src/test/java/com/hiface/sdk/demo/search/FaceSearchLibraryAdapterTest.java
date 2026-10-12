package com.hiface.sdk.demo.search;

import androidx.recyclerview.widget.DiffUtil;
import androidx.recyclerview.widget.ListUpdateCallback;

import com.hiface.sdk.search.FaceSearchEntry;
import org.junit.Test;

import java.util.Arrays;
import java.util.List;

import static org.junit.Assert.*;

public final class FaceSearchLibraryAdapterTest {
    private static Object action(FaceSearchLibraryAdapter.PendingCommit commit) throws Exception {
        java.lang.reflect.Field field = commit.getClass().getDeclaredField("action");
        field.setAccessible(true);
        return field.get(commit);
    }

    @Test public void cancelledCommitDropsPageClosureBeforeDiffCompletes() throws Exception {
        FaceSearchLibraryAdapter.PendingCommit commit =
                new FaceSearchLibraryAdapter.PendingCommit(() -> fail("Cancelled Diff reached page"));
        assertNotNull(action(commit));
        commit.cancel();
        assertNull(action(commit));
        commit.run(); commit.run();
    }

    @Test public void completedCommitDropsClosureBeforeInvokingIt() throws Exception {
        int[] calls = {0};
        FaceSearchLibraryAdapter.PendingCommit[] commit = new FaceSearchLibraryAdapter.PendingCommit[1];
        commit[0] = new FaceSearchLibraryAdapter.PendingCommit(() -> {
            calls[0]++;
            try { assertNull(action(commit[0])); }
            catch (Exception error) { throw new AssertionError(error); }
        });
        commit[0].run(); commit[0].run();
        assertEquals(1, calls[0]);
    }

    private static FaceSearchEntry entry(String id,String group,int featureIndex,String tag) {
        String feature="HF1:"+new String(new char[600]).replace('\0','A');
        return new FaceSearchEntry(id,feature,featureIndex,tag,group);
    }
    private static DiffUtil.DiffResult diff(List<FaceSearchStore.Person> before,List<FaceSearchStore.Person> after) {
        return DiffUtil.calculateDiff(new DiffUtil.Callback() {
            @Override public int getOldListSize(){return before.size();}
            @Override public int getNewListSize(){return after.size();}
            @Override public boolean areItemsTheSame(int oldIndex,int newIndex){return FaceSearchLibraryAdapter.DIFF.areItemsTheSame(before.get(oldIndex),after.get(newIndex));}
            @Override public boolean areContentsTheSame(int oldIndex,int newIndex){return FaceSearchLibraryAdapter.DIFF.areContentsTheSame(before.get(oldIndex),after.get(newIndex));}
        });
    }
    private static final class Updates implements ListUpdateCallback {
        int inserted,removed,changed,moved;
        @Override public void onInserted(int position,int count){inserted+=count;}
        @Override public void onRemoved(int position,int count){removed+=count;}
        @Override public void onMoved(int from,int to){moved++;}
        @Override public void onChanged(int position,int count,Object payload){changed+=count;}
    }
    @Test public void refreshedFeaturesDoNotRebindUnchangedCards() {
        List<FaceSearchStore.Person> before=FaceSearchStore.people(Arrays.asList(entry("A","1A",0,"VIP"),entry("B","",0,"guest")));
        List<FaceSearchStore.Person> after=FaceSearchStore.people(Arrays.asList(entry("A","1A",1,"VIP"),entry("B","",2,"guest")));
        Updates updates=new Updates();diff(before,after).dispatchUpdatesTo(updates);
        assertEquals(0,updates.inserted+updates.removed+updates.changed+updates.moved);
    }
    @Test public void groupChangesUpdateOnlyTheAffectedCard() {
        List<FaceSearchStore.Person> before=FaceSearchStore.people(Arrays.asList(entry("A","1A",0,""),entry("B","2B",0,"")));
        List<FaceSearchStore.Person> after=FaceSearchStore.people(Arrays.asList(entry("A","",0,""),entry("B","2B",0,"")));
        Updates updates=new Updates();diff(before,after).dispatchUpdatesTo(updates);
        assertEquals(1,updates.changed);assertEquals(0,updates.inserted+updates.removed+updates.moved);
    }
    @Test public void tagChangesUpdateOnlyTheAffectedCard() {
        List<FaceSearchStore.Person> before=FaceSearchStore.people(Arrays.asList(entry("A","1A",0,"old"),entry("B","2B",0,"")));
        List<FaceSearchStore.Person> after=FaceSearchStore.people(Arrays.asList(entry("A","1A",0,"new"),entry("B","2B",0,"")));
        Updates updates=new Updates();diff(before,after).dispatchUpdatesTo(updates);
        assertEquals(1,updates.changed);assertEquals(0,updates.inserted+updates.removed+updates.moved);
    }
    @Test public void deletingFirstRowMovesRemainingIdentityWithoutRebindingAllRows() {
        List<FaceSearchStore.Person> before=FaceSearchStore.people(Arrays.asList(entry("A","1A",0,""),entry("B","1A",0,""),entry("C","1A",0,"")));
        List<FaceSearchStore.Person> after=FaceSearchStore.people(Arrays.asList(entry("B","1A",0,""),entry("C","1A",0,"")));
        DiffUtil.DiffResult diff=diff(before,after);Updates updates=new Updates();diff.dispatchUpdatesTo(updates);
        assertEquals(1,updates.removed);assertEquals(0,updates.inserted+updates.changed);
        assertEquals(DiffUtil.DiffResult.NO_POSITION,diff.convertOldPositionToNew(0));
        assertEquals(0,diff.convertOldPositionToNew(1));assertEquals(1,diff.convertOldPositionToNew(2));
    }
    @Test public void idsWithSameHashAreStillDifferentPeople() {
        assertEquals("Aa".hashCode(),"BB".hashCode());
        List<FaceSearchStore.Person> before=FaceSearchStore.people(Arrays.asList(entry("Aa","1A",0,"")));
        List<FaceSearchStore.Person> after=FaceSearchStore.people(Arrays.asList(entry("BB","1A",0,"")));
        Updates updates=new Updates();diff(before,after).dispatchUpdatesTo(updates);
        assertEquals(1,updates.removed);assertEquals(1,updates.inserted);assertEquals(0,updates.changed);
    }
}
