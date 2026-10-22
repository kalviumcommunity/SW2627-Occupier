const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  collection,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  serverTimestamp,
  updateDoc,
  where,
  writeBatch,
} = require('firebase/firestore');
const { getBytes, ref, uploadBytes } = require('firebase/storage');
const { test, before, after, beforeEach } = require('node:test');

const projectId = 'occupier-rules-test';
const firestoreRules = fs.readFileSync(
  path.resolve(__dirname, '..', 'firestore.rules'),
  'utf8',
);
const storageRules = fs.readFileSync(
  path.resolve(__dirname, '..', 'storage.rules'),
  'utf8',
);
const mobileFirestoreRules = fs.readFileSync(
  path.resolve(__dirname, '..', 'mobile', 'firestore.rules'),
  'utf8',
);
const rootFirebaseConfig = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '..', 'firebase.json'), 'utf8'),
);
const mobileFirebaseConfig = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, '..', 'mobile', 'firebase.json'), 'utf8'),
);

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: firestoreRules,
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: storageRules,
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

test('Firebase configurations point to identical Firestore rules', () => {
  assert.equal(rootFirebaseConfig.firestore.rules, 'firestore.rules');
  assert.equal(mobileFirebaseConfig.firestore.rules, 'firestore.rules');
  assert.equal(mobileFirestoreRules, firestoreRules);
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'member-1'), {
      uid: 'member-1',
      name: 'Test Member',
      email: 'member@example.com',
      role: 'member',
      photoUrl: null,
    });
    await setDoc(doc(db, 'branches', 'branch-1'), {
      name: 'Branch One',
      address: '1 Example Street',
      city: 'Example City',
      contactNumber: '123456789',
      totalDeskCapacity: 10,
      totalRoomCapacity: 2,
      openingTime: '09:00',
      closingTime: '18:00',
      status: 'active',
      managerUid: 'manager-1',
      staffUids: ['staff-1'],
    });
    await setDoc(doc(db, 'branches', 'branch-1', 'desks', 'desk-1'), {
      name: 'Desk 1',
      type: 'hotDesk',
      floor: '1',
      status: 'available',
    });
  });
});

function validBooking(overrides = {}) {
  const startTime = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  startTime.setUTCHours(10, 0, 0, 0);
  const booking = {
    userId: 'member-1',
    createdBy: 'member-1',
    branchId: 'branch-1',
    resourceId: 'desk-1',
    resourceType: 'desk',
    status: 'confirmed',
    startTime,
    endTime: new Date(startTime.getTime() + 60 * 60 * 1000),
    ...overrides,
  };
  const dateKey = new Date(
    booking.startTime.getTime() + 330 * 60 * 1000,
  ).toISOString().slice(0, 10);

  return {
    ...booking,
    reservationScheduleId:
      booking.reservationScheduleId ??
      `${booking.branchId}__${booking.resourceType}__${booking.resourceId}__${dateKey}`,
  };
}

async function writeBooking(db, bookingId = 'booking-1', overrides = {}) {
  const booking = validBooking(overrides);
  const batch = writeBatch(db);
  const bookingRef = doc(db, 'bookings', bookingId);
  const scheduleRef = doc(
    db,
    'booking_schedules',
    booking.reservationScheduleId,
  );

  batch.set(bookingRef, { ...booking, createdAt: serverTimestamp() });
  batch.set(scheduleRef, {
    branchId: booking.branchId,
    resourceId: booking.resourceId,
    resourceType: booking.resourceType,
    dateKey: booking.reservationScheduleId.split('__').pop(),
    reservations: {
      [bookingId]: {
        bookingId,
        startTime: booking.startTime,
        endTime: booking.endTime,
        status: booking.status,
      },
    },
    lastBookingId: bookingId,
    updatedAt: serverTimestamp(),
  });
  await batch.commit();
}

async function cancelBookingAtomically(
  db,
  bookingId = 'booking-1',
  { readDb = db } = {},
) {
  const bookingRef = doc(readDb, 'bookings', bookingId);
  const bookingSnapshot = await getDoc(bookingRef);

  if (!bookingSnapshot.exists()) {
    throw new Error(`Booking ${bookingId} was not found.`);
  }

  const booking = bookingSnapshot.data();
  const scheduleId = booking.reservationScheduleId;

  const scheduleRef = doc(readDb, 'booking_schedules', scheduleId);
  const scheduleSnapshot = await getDoc(scheduleRef);

  if (!scheduleSnapshot.exists()) {
    throw new Error(`Schedule ${scheduleId} was not found.`);
  }

  const schedule = scheduleSnapshot.data();
  const currentReservation = schedule.reservations?.[bookingId];

  if (!currentReservation) {
    throw new Error(`Reservation ${bookingId} was not found.`);
  }

  const reservations = {
    ...schedule.reservations,
    [bookingId]: {
      ...currentReservation,
      status: 'cancelled',
    },
  };

  // Use one atomic batch for both document updates.
  // `db` is the identity performing the writes; `readDb` can be
  // the owner's context when testing an unauthorized user's attempt.
  const batch = writeBatch(db);

  batch.update(doc(db, 'bookings', bookingId), {
    status: 'cancelled',
  });

  batch.update(doc(db, 'booking_schedules', scheduleId), {
    reservations,
    lastBookingId: bookingId,
    updatedAt: serverTimestamp(),
  });

  await batch.commit();
}

function validBranch(overrides = {}) {
  return {
    name: 'Branch Two',
    address: '2 Example Street',
    city: 'Example City',
    contactNumber: '123456789',
    totalDeskCapacity: 10,
    totalRoomCapacity: 2,
    openingTime: '09:00',
    closingTime: '18:00',
    status: 'active',
    staffUids: [],
    ...overrides,
  };
}

function validOccupancy(overrides = {}) {
  return {
    occupancyId: 'occupancy-1',
    branchId: 'branch-1',
    resourceId: 'desk-1',
    resourceType: 'desk',
    userId: 'member-1',
    bookingId: 'booking-1',
    status: 'active',
    checkInTime: new Date('2026-10-16T08:00:00Z'),
    checkOutTime: null,
    source: 'booking',
    createdAt: new Date('2026-10-16T08:00:00Z'),
    ...overrides,
  };
}

test('denies unauthenticated access to private application data', async () => {
  const db = testEnv.unauthenticatedContext().firestore();

  await assertFails(getDoc(doc(db, 'users', 'member-1')));
  await assertFails(getDoc(doc(db, 'branches', 'branch-1')));
  await assertFails(getDoc(doc(db, 'bookings', 'booking-1')));
  await assertFails(getDoc(doc(db, 'occupancies', 'occupancy-1')));
});

test('allows a user to read and update permitted fields in their profile', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await assertSucceeds(getDoc(doc(db, 'users', 'member-1')));
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'member-1'), {
      name: 'Updated Member',
      photoUrl: 'https://example.com/member.jpg',
    }),
  );
});

test('denies reading or updating another user profile', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await assertFails(getDoc(doc(db, 'users', 'other-user')));
  await assertFails(
    updateDoc(doc(db, 'users', 'other-user'), { name: 'Changed' }),
  );
});

test('allows a new account to create only a valid member profile', async () => {
  const db = testEnv.authenticatedContext('new-member').firestore();

  await assertSucceeds(
    setDoc(doc(db, 'users', 'new-member'), {
      uid: 'new-member',
      name: 'New Member',
      email: 'new@example.com',
      role: 'member',
      photoUrl: null,
    }),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'attacker'), {
      uid: 'attacker',
      name: 'Attacker',
      email: 'attacker@example.com',
      role: 'admin',
    }),
  );
});

test('denies ordinary users from changing roles or adding authorization fields', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await assertFails(
    updateDoc(doc(db, 'users', 'member-1'), { role: 'admin' }),
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'member-1'), { isAdmin: true }),
  );
  await assertFails(
    updateDoc(doc(db, 'users', 'member-1'), { name: 12 }),
  );
  await assertFails(
    setDoc(doc(db, 'users', 'member-1'), {
      uid: 'member-1',
      name: 'Member',
      email: 'member@example.com',
      role: 'member',
      assignedBranchId: 'branch-1',
    }),
  );
});

test('fails closed for missing and invalid profile role data', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'no-role'), {
      uid: 'no-role',
      name: 'No Role',
      email: 'no-role@example.com',
    });
    await setDoc(doc(db, 'users', 'invalid-role'), {
      uid: 'invalid-role',
      name: 'Invalid Role',
      email: 'invalid-role@example.com',
      role: 12,
    });
  });

  const missingRoleDb = testEnv.authenticatedContext('no-role').firestore();
  const invalidRoleDb = testEnv.authenticatedContext('invalid-role').firestore();

  await assertFails(
    setDoc(doc(missingRoleDb, 'branches', 'branch-2'), validBranch()),
  );
  await assertFails(
    setDoc(doc(invalidRoleDb, 'branches', 'branch-2'), validBranch()),
  );
});

test('allows a user to create and query only their own bookings', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();
  const booking = validBooking();

  await assertSucceeds(writeBooking(db, 'booking-1', booking));
  const ownBookings = await assertSucceeds(
    getDocs(
      query(
        collection(db, 'bookings'),
        where('userId', '==', 'member-1'),
      ),
    ),
  );
  if (ownBookings.size !== 1) {
    throw new Error(`Expected one own booking, got ${ownBookings.size}`);
  }
  await assertFails(getDoc(doc(db, 'bookings', 'someone-elses-booking')));
  await assertSucceeds(
    getDoc(
      doc(
        db,
        'booking_schedules',
        booking.reservationScheduleId,
      ),
    ),
  );
  await assertFails(getDocs(collection(db, 'booking_schedules')));

  const otherUserDb = testEnv.authenticatedContext('member-2').firestore();
  await assertFails(getDoc(doc(otherUserDb, 'bookings', 'booking-1')));
});

test('ordinary users can query only their own occupancy records', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(
      doc(db, 'occupancies', 'member-occupancy'),
      validOccupancy({ userId: 'member-1' }),
    );
    await setDoc(
      doc(db, 'occupancies', 'other-occupancy'),
      validOccupancy({
        occupancyId: 'other-occupancy',
        userId: 'member-2',
      }),
    );
  });

  const db = testEnv.authenticatedContext('member-1').firestore();
  const ownOccupancies = await assertSucceeds(
    getDocs(
      query(
        collection(db, 'occupancies'),
        where('status', '==', 'active'),
        where('userId', '==', 'member-1'),
      ),
    ),
  );

  assert.equal(ownOccupancies.size, 1);
  await assertFails(
    getDocs(
      query(
        collection(db, 'occupancies'),
        where('status', '==', 'active'),
      ),
    ),
  );
});

test('denies users from creating or changing unauthorized bookings', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await assertFails(
    setDoc(
      doc(db, 'bookings', 'other-owner-booking'),
      validBooking({ userId: 'other-user', createdBy: 'other-user' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(db, 'bookings', 'invalid-booking'),
      validBooking({ status: 'completed' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(db, 'bookings', 'extra-field-booking'),
      validBooking({ role: 'admin' }),
    ),
  );
  await assertFails(
    setDoc(
      doc(db, 'bookings', 'wrong-schedule-booking'),
      validBooking({ reservationScheduleId: 'another-resource__2026-11-02' }),
    ),
  );

  await writeBooking(db);

// A booking cannot be cancelled without updating its schedule atomically.
await assertFails(
  updateDoc(doc(db, 'bookings', 'booking-1'), { status: 'cancelled' }),
);
  await assertFails(
    updateDoc(doc(db, 'bookings', 'booking-1'), {
      status: 'cancelled',
      userId: 'other-user',
    }),
  );
});

test('booking owner can atomically cancel a booking and its reservation', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await writeBooking(db);

  await assertSucceeds(cancelBookingAtomically(db, 'booking-1'));

  const bookingSnapshot = await getDoc(
    doc(db, 'bookings', 'booking-1'),
  );

  if (bookingSnapshot.data()?.status !== 'cancelled') {
    throw new Error('Booking status was not updated to cancelled.');
  }

  const scheduleId = bookingSnapshot.data().reservationScheduleId;
  const scheduleSnapshot = await getDoc(
    doc(db, 'booking_schedules', scheduleId),
  );

  if (
    scheduleSnapshot.data()?.reservations?.['booking-1']?.status !==
    'cancelled'
  ) {
    throw new Error('Schedule reservation status was not updated.');
  }
});

test('another user cannot atomically cancel someone else booking', async () => {
  const ownerDb = testEnv.authenticatedContext('member-1').firestore();
  const otherUserDb = testEnv.authenticatedContext('member-2').firestore();

  await writeBooking(ownerDb);

  // Read the existing records as the owner, but attempt both writes
  // under member-2's identity.
  await assertFails(
    cancelBookingAtomically(otherUserDb, 'booking-1', {
      readDb: ownerDb,
    }),
  );
});

test('ordinary users cannot modify branches or resource availability', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await assertFails(
    updateDoc(doc(db, 'branches', 'branch-1'), { status: 'inactive' }),
  );
  await assertFails(
    setDoc(
      doc(db, 'branches', 'branch-1', 'desks', 'desk-2'),
      {
        name: 'Desk 2',
        type: 'hotDesk',
        floor: '1',
        status: 'available',
      },
    ),
  );
  await assertFails(
    updateDoc(
      doc(db, 'branches', 'branch-1', 'desks', 'desk-1'),
      { status: 'occupied' },
    ),
  );
});

test('an administrator can perform protected administrative operations', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'admin-1'), {
      uid: 'admin-1',
      name: 'Admin',
      email: 'admin@example.com',
      role: 'admin',
    });
  });

  const db = testEnv.authenticatedContext('admin-1').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'users', 'member-1'), { role: 'staff' }),
  );
  await assertSucceeds(
    setDoc(doc(db, 'branches', 'branch-2'), validBranch()),
  );
  await assertSucceeds(
    setDoc(doc(db, 'branches', 'branch-2', 'desks', 'desk-1'), {
      name: 'Desk 1',
      type: 'hotDesk',
      floor: '1',
      status: 'available',
    }),
  );
});

test('branch managers can create valid resources only in their assigned branch', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'manager-1'), {
      uid: 'manager-1',
      name: 'Manager',
      email: 'manager@example.com',
      role: 'branchManager',
    });
  });

  const db = testEnv.authenticatedContext('manager-1').firestore();
  const desk = {
    name: 'Desk 1',
    type: 'hotDesk',
    floor: '1',
    status: 'available',
  };

  await assertSucceeds(
    setDoc(doc(db, 'branches', 'branch-1', 'desks', 'desk-1'), desk),
  );
  await assertFails(
    setDoc(doc(db, 'branches', 'branch-2', 'desks', 'desk-1'), desk),
  );
  await assertFails(
    setDoc(doc(db, 'branches', 'branch-1', 'desks', 'invalid-desk'), {
      ...desk,
      isAdmin: true,
    }),
  );
});

test('branch staff can manage occupancy only in an assigned branch', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, 'users', 'staff-1'), {
      uid: 'staff-1',
      name: 'Staff',
      email: 'staff@example.com',
      role: 'staff',
    });
    await setDoc(doc(db, 'occupancies', 'occupancy-1'), validOccupancy());
  });

  const staffDb = testEnv.authenticatedContext('staff-1').firestore();
  await assertSucceeds(
    updateDoc(doc(staffDb, 'occupancies', 'occupancy-1'), {
      status: 'completed',
      checkOutTime: new Date('2026-10-16T10:00:00Z'),
    }),
  );
  await assertFails(
    updateDoc(doc(staffDb, 'occupancies', 'occupancy-1'), {
      status: 'completed',
      checkOutTime: new Date('2026-10-16T10:00:00Z'),
      branchId: 'branch-2',
    }),
  );
});

test('assigned staff can create walk-in occupancy only in their branch', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'users', 'staff-1'), {
      uid: 'staff-1',
      name: 'Staff',
      email: 'staff@example.com',
      role: 'staff',
    });
  });

  const db = testEnv.authenticatedContext('staff-1').firestore();
  const occupancy = {
    occupancyId: 'walk-in-1',
    branchId: 'branch-1',
    resourceId: 'desk-1',
    resourceType: 'desk',
    userId: 'walk-in-user',
    bookingId: null,
    status: 'active',
    checkInTime: serverTimestamp(),
    checkOutTime: null,
    source: 'walkIn',
    createdAt: serverTimestamp(),
  };

  await assertSucceeds(setDoc(doc(db, 'occupancies', 'walk-in-1'), occupancy));
  await assertFails(
    setDoc(doc(db, 'occupancies', 'walk-in-2'), {
      ...occupancy,
      occupancyId: 'walk-in-2',
      branchId: 'branch-2',
    }),
  );
});

test('a member can create occupancy linked to their confirmed booking', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'bookings', 'booking-1'),
      validBooking(),
    );
  });

  const db = testEnv.authenticatedContext('member-1').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'occupancies', 'occupancy-1'), {
      occupancyId: 'occupancy-1',
      branchId: 'branch-1',
      resourceId: 'desk-1',
      resourceType: 'desk',
      userId: 'member-1',
      bookingId: 'booking-1',
      status: 'active',
      checkInTime: serverTimestamp(),
      checkOutTime: null,
      source: 'booking',
      createdAt: serverTimestamp(),
    }),
  );
});

test('users cannot create an unlinked self-occupancy or claim another user', async () => {
  const db = testEnv.authenticatedContext('member-1').firestore();

  await assertFails(
    setDoc(
      doc(db, 'occupancies', 'occupancy-1'),
      validOccupancy({
        bookingId: null,
        source: 'walkIn',
        checkInTime: new Date(),
        createdAt: new Date(),
      }),
    ),
  );
  await assertFails(
    setDoc(
      doc(db, 'occupancies', 'occupancy-2'),
      validOccupancy({
        occupancyId: 'occupancy-2',
        userId: 'other-user',
        checkInTime: new Date(),
        createdAt: new Date(),
      }),
    ),
  );
});

test('a user can access only their own profile image in Storage', async () => {
  const ownerStorage = testEnv.authenticatedContext('photo-owner').storage();
  const otherStorage = testEnv.authenticatedContext('other-user').storage();
  const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const ownerRef = ref(ownerStorage, 'profile_photos/photo-owner.jpg');

  await assertSucceeds(
    uploadBytes(ownerRef, image, { contentType: 'image/jpeg' }),
  );
  await assertSucceeds(getBytes(ownerRef));
  await assertFails(
    getBytes(ref(otherStorage, 'profile_photos/photo-owner.jpg')),
  );
  await assertFails(
    uploadBytes(
      ref(otherStorage, 'profile_photos/photo-owner.jpg'),
      image,
      { contentType: 'image/jpeg' },
    ),
  );
  await assertFails(
    uploadBytes(
      ref(ownerStorage, 'profile_photos/photo-owner.png'),
      image,
      { contentType: 'image/png' },
    ),
  );
});
