Product Requirements Document (PRD):


Project: Occupier — Smart Co-working Space Occupancy & Booking System
Version: 1.0
Platform: Mobile application
Primary technology: Flutter + Dart
Backend: Firebase
Authentication: Firebase Authentication
Database: Cloud Firestore
File storage: Firebase Storage
Development/Testing: Firebase Emulator Suite + Physical/Android/iOS devices

1. Product Overview
Occupier is a centralized co-working space management application designed to give a chain of co-working spaces a real-time view of occupancy, bookings, and utilization across all branches.
The system will replace independent branch-level tracking with a centralized platform where:
- Members can book desks and meeting rooms.
- Walk-in users can be checked in by branch staff.
- Branch staff can manage their location's occupancy.
- Central administrators can monitor utilization across all locations.
- The system prevents conflicting/double bookings.
- Historical utilization data supports future expansion and capacity decisions.
Core product goal
Provide a single source of truth for desk and meeting-room availability across all co-working locations in real time.

2. Problem Statement
A chain of co-working spaces currently manages desk and meeting-room bookings independently at each branch.
This creates several problems:
1. The central team has no live view of occupancy.
2. High-demand desks and rooms can be double-allocated.
3. Walk-in users are not consistently reflected in occupancy data.
4. Branches operate with fragmented booking information.
5. Historical utilization data is unreliable or difficult to aggregate.
6. Expansion decisions are made without accurate occupancy insights.
Occupier addresses these problems through a centralized, Firebase-backed booking and occupancy system.
3. Product Goals
Primary goals
Goal	Description
Centralized bookings	Maintain bookings for every branch in one system
Real-time occupancy	Show current occupancy across locations
Prevent double booking	Ensure a desk/room cannot be booked by multiple users for overlapping periods
Walk-in management	Allow staff to check in walk-in users
Branch management	Allow branch staff to manage their own location
Utilization analytics	Track historical usage and occupancy
Scalability	Support additional branches, desks and rooms


Secondary goals
- Reduce manual branch-level tracking.
- Improve member booking experience.
- Help management identify high-demand locations/time slots.
- Provide data for expansion planning.
- Create a foundation for future features such as payments and subscriptions.

4. Non-Goals — Version 1
To keep the first version manageable, the following are out of scope:
- Online payments.
- Subscription/billing management.
- Automated IoT occupancy sensors.
- Facial recognition.
- Advanced AI-based demand prediction.
- Access-control hardware integration.
- External calendar integrations.
- Complex loyalty/rewards systems.
These can be considered in future versions.

5. User Roles
Occupier should have three primary user roles.
5.1 Central Admin
The central admin manages the entire co-working network.
Responsibilities
- View all branches.
- View live occupancy.
- View bookings.
- Create/manage branches.
- Manage branch staff.
- Add desks and meeting rooms.
- View utilization analytics.
- Identify high-demand locations/time periods.
5.2 Branch Manager / Staff
Branch staff manage a specific location.
Responsibilities
- View branch occupancy.
- View today's bookings.
- Check in walk-in users.
- Check out users.
- Create bookings when necessary.
- Manage desks/rooms at their branch.
- View branch utilization.
Branch staff should not be able to modify other branches.
5.3 Member / Customer
Members interact with the application to use the co-working spaces.
Responsibilities
- Browse branches.
- View available desks/rooms.
- Make bookings.
- View upcoming bookings.
- Cancel bookings.
- Check booking status.
- Check in when arriving.

6. Core User Journeys
Journey 1 — Member books a desk
Login
  ↓
Select Location
  ↓
Select Date
  ↓
Select Time
  ↓
View Available Desks
  ↓
Select Desk
  ↓
Confirm Booking
  ↓
Booking Created
  ↓
Confirmation

Journey 2 — Member books a meeting room
Login
  ↓
Select Location
  ↓
Meeting Rooms
  ↓
Select Date + Time
  ↓
View Available Rooms
  ↓
Select Room
  ↓
Confirm
  ↓
Booking Created

Journey 3 — Walk-in user
Customer arrives
       ↓
Branch staff opens Walk-in
       ↓
Select desk/room
       ↓
Enter customer details
       ↓
Select duration
       ↓
Check-in
       ↓
Occupancy updated
       ↓
Customer leaves
       ↓
Check-out

Journey 4 — Central admin checks occupancy
Admin Login
     ↓
Dashboard
     ↓
All Locations
     ↓
Live Occupancy
     ↓
Select Branch
     ↓
View:
 ├── Total capacity
 ├── Current occupancy
 ├── Available desks
 ├── Occupied desks
 ├── Meeting-room usage
 └── Today's bookings

7. Functional Requirements
7.1 Authentication
The application must provide secure authentication using Firebase Authentication.
Features
- Email/password login.
- User registration.
- Logout.
- Password reset.
- Session persistence.
- Role-based access.
User profile
Each user should have:
User
├── uid
├── name
├── email
├── phone
├── role
├── assignedBranchId
├── profileImage
├── createdAt
└── status

Possible roles:
admin
branch_manager
staff
member

8. Branch Management
Central administrators can create and manage branches.
Branch information
Branch
├── branchId
├── name
├── address
├── city
├── contactNumber
├── totalDeskCapacity
├── totalRoomCapacity
├── openingTime
├── closingTime
├── status
├── imageUrl
└── createdAt

Requirements
Admin can:
- Create branch.
- Edit branch.
- Activate/deactivate branch.
- View branch.
- Assign staff.
- View branch statistics.

9. Desk Management
Each branch contains multiple desks.
Desk properties
Desk
├── deskId
├── branchId
├── name/number
├── type
├── floor
├── status
└── createdAt

Desk types could include:
- Hot desk
- Dedicated desk
- Premium desk
Desk status
available
occupied
maintenance
inactive

However, booking availability should not rely solely on the status field.
Availability should be calculated from bookings and active occupancy records.

10. Meeting Room Management
Each branch can contain multiple meeting rooms.
Meeting room properties
MeetingRoom
├── roomId
├── branchId
├── name
├── capacity
├── floor
├── amenities
├── status
└── createdAt

Example amenities:
Projector
Whiteboard
Video conferencing
TV
Conference phone

11. Booking System
This is the most important component of the system.
A booking should contain:
Booking
├── bookingId
├── userId
├── branchId
├── resourceId
├── resourceType
├── startTime
├── endTime
├── status
├── createdAt
└── createdBy

Where:
resourceType =
    desk
    room

12. Double-Booking Prevention
This is a critical requirement.
Before creating a booking, the system must verify that the selected resource is not already booked for an overlapping time period.
For example:
Existing booking:
10:00 ───────── 12:00

New booking:
         11:00 ─────── 13:00

          ❌ Conflict
But:
Existing:
10:00 ───── 12:00

New:
12:00 ───────── 14:00

          ✅ Allowed
Important implementation requirement
Booking creation should use a Firestore transaction or another atomic server-side approach so that two users attempting to book the same resource simultaneously cannot both succeed.
The UI availability check alone is not sufficient.
13. Real-Time Occupancy
Firestore's real-time listeners should be used to keep occupancy information synchronized.
For example:
Branch A

Capacity: 100

Occupied: 73
Available: 27

Occupancy: 73%
When a member checks in:
73 → 74
All authorized clients listening to that branch should see the updated state without manually refreshing.
14. Check-In / Check-Out
Occupier should distinguish between:
Booking
A reservation for a future/current time.
Actual occupancy
Whether the user has physically checked in.
This distinction is important because:
Booked ≠ Occupied
Example:
50 desks are booked but only 35 users have checked in.
The central team should be able to see both numbers.
15. Walk-In Management
Branch staff should have a dedicated Walk-In flow.
Walk-in process
Staff selects:
Walk-in
 ↓
Customer
 ↓
Resource
 ↓
Duration
 ↓
Check-in
The system creates an occupancy record and optionally a booking record marked as:
bookingSource = walk_in
This ensures walk-ins are included in utilization data.
16. Dashboard
The dashboard is the primary management screen.
Central Admin Dashboard
Example:
Good Morning, Admin

Network Occupancy
━━━━━━━━━━━━━━━━━━━━
1,284 / 1,850
69.4%

Branches
━━━━━━━━━━━━━━━━━━━━

Jaipur          82%  🔴
Delhi           74%  🟠
Mumbai          61%  🟢
Bangalore       87%  🔴

Today's Bookings
━━━━━━━━━━━━━━━━━━━━
Desks             623
Meeting Rooms      87
Walk-ins           42
17. Branch Dashboard
Branch staff should see:
Branch: Jaipur Central

Current Occupancy
━━━━━━━━━━━━━━━━
74 / 100
74%

Desks
Available       26
Occupied        74

Meeting Rooms
Available        3
Occupied         2

Today's Bookings
━━━━━━━━━━━━━━━━
09:00  Desk 24
10:00  Room A
11:30  Desk 42
18. Analytics
The central team needs historical data rather than only current occupancy.
Key metricsOccupancy Rate
Occupied Capacity
────────────────── × 100
Total Capacity
Booking Utilization
Booked Resource Hours
────────────────────── × 100
Available Resource Hours
Analytics should support
Daily occupancy.
Weekly occupancy.
Monthly occupancy.
Branch comparison.
Desk utilization.
Meeting-room utilization.
Peak hours.
Walk-in volume.
Booking cancellations.
No-shows.
19. Expansion Insights
One of the key business purposes of the application is to improve expansion decisions.
The admin should eventually be able to identify:
Branch       Avg Occupancy     Peak Occupancy
------------------------------------------------
Jaipur            82%               96%
Delhi             76%               91%
Mumbai            61%               73%
Bangalore         88%               98%
This allows management to identify:
Underutilized locations.
Locations approaching capacity.
High-demand time periods.
Locations where additional desks may be needed.
Locations that may justify expansion.
20. Notifications
For MVP, notifications can be relatively simple.
Users should receive notifications for:
Booking confirmation.
Booking cancellation.
Booking reminder.
Booking conflict.
Check-in confirmation.
Later versions can introduce push notifications using Firebase Cloud Messaging.
21. Firebase Architecture
A suitable architecture would be:
              Flutter App
                  │
          ┌───────┴───────┐
          │               │
 Firebase Auth       Cloud Firestore
          │               │
          │        ┌──────┴──────┐
          │        │             │
          │     Bookings      Occupancy
          │        │             │
          │        └──────┬──────┘
          │               │
          │        Branch / Resources
          │
     Firebase Storage
          │
    Profile / Branch
       Images
22. Proposed Firestore Structure
A scalable structure could be:
/users/{userId}

/branches/{branchId}

/branches/{branchId}/desks/{deskId}

/branches/{branchId}/rooms/{roomId}

/bookings/{bookingId}

/occupancy/{occupancyId}
Potentially:
/branches/{branchId}/staff/{userId}
for branch-specific staff assignments.