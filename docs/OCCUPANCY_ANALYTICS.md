# Historical occupancy analytics

The staff-only analytics screen reports daily, Monday-to-Sunday weekly, and
calendar-month periods. Each range is start-inclusive and end-exclusive.
Completed records are selected by `checkOutTime > range.start` and
`checkInTime < range.end`; active records are selected by `checkInTime <
range.end`. Results use 200-document cursor pages and are de-duplicated by
occupancy document ID before aggregation. Staff and branch managers always
query one assigned branch at a time; only administrators issue a network query.
Firestore rules independently enforce those branch and role restrictions.

The completed-record overlap query uses multiple inequalities and requires the
composite indexes in `firestore.indexes.json` (also mirrored in
`mobile/firestore.indexes.json`). Deploy them with
`firebase deploy --only firestore:indexes` from the repository root, or with
`firebase deploy --only firestore:indexes --config mobile/firebase.json` from
the mobile directory.

Sessions are clipped to the selected range. Active sessions without a checkout
end at the earlier of the report end and the current time. Invalid or
zero-duration sessions do not contribute. The report counts unique sessions
and occupied resource-hours, including room occupancy time. It does not expose
walk-in contact details.

The current data has no historical resource-capacity snapshots and no
per-session room attendance. Therefore the report intentionally does not show
historical utilization percentages or occupied seat-hours. Resource-hours
must not be interpreted as seat-hours. A future improvement should record
effective-dated resource capacities and room attendance/seat counts.

The query avoids a full collection scan by filtering records on their status
and overlap timestamps. Its result size is nevertheless proportional to the
number of sessions overlapping a requested period; completed sessions that
started before the period must remain eligible, regardless of how late they
checked out. If query volume becomes too large, add a maintained
`occupancy_daily` overlap rollup or effective-dated interval index rather than
truncating results and silently omitting sessions.
