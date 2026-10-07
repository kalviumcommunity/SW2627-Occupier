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
CUSTOMER
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

23. Firestore Booking Example
{
  "userId": "user_123",
  "branchId": "branch_jaipur",
  "resourceId": "desk_42",
  "resourceType": "desk",
  "startTime": "2026-10-05T10:00:00",
  "endTime": "2026-10-05T14:00:00",
  "status": "confirmed",
  "source": "member",
  "createdAt": "..."
}
24. Occupancy Record
{
  "userId": "user_123",
  "branchId": "branch_jaipur",
  "resourceId": "desk_42",
  "checkInTime": "...",
  "checkOutTime": null,
  "status": "active",
  "source": "booking"
}
When the user checks out:
status: active
      ↓
status: completed
checkOutTime: timestamp
25. Flutter Application Architecture
For a university project, I'd recommend keeping the Flutter architecture clean but not unnecessarily complicated.
lib/
│
├── core/
│   ├── constants/
│   ├── theme/
│   ├── utils/
│   └── services/
│
├── models/
│   ├── user.dart
│   ├── branch.dart
│   ├── desk.dart
│   ├── meeting_room.dart
│   ├── booking.dart
│   └── occupancy.dart
│
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── branches/
│   ├── desks/
│   ├── meeting_rooms/
│   ├── bookings/
│   ├── occupancy/
│   └── profile/
│
└── main.dart
For state management, Riverpod or Bloc would fit well, although it isn't strictly required by your stated stack.
26. Firebase Services
Requirement
Firebase Service
Login/signup
Firebase Authentication
User profiles
Cloud Firestore
Branch data
Cloud Firestore
Desk data
Cloud Firestore
Room data
Cloud Firestore
Bookings
Cloud Firestore
Live occupancy
Cloud Firestore
Images
Firebase Storage
Push notifications
Firebase Cloud Messaging
Backend validation/logic
Cloud Functions
Local testing
Firebase Emulator Suite
You haven't listed Cloud Functions, but I'd strongly recommend adding it to the stack for production-grade booking validation and privileged backend operations.
27. Security Requirements
Security is particularly important because users should not be able to modify another branch's data.
Example access rules
Admin
Read/write:
All branches
All bookings
All occupancy
Branch Staff
Read/write:
Assigned branch
Read:
Relevant bookings/occupancy
Member
Read:
Available branches/resources
Create:
Own bookings
Read/update:
Own bookings
A member should never be able to simply modify:
booking.userId
booking.branchId
booking.status
through a manipulated client request.
These permissions should be enforced through Firestore Security Rules, not only Flutter UI logic.
28. MVP Scope
For a university project, I'd make the MVP:
Authentication
Registration
Login
Logout
Role-based access
Member
View branches
View available desks
View meeting rooms
Book resource
View bookings
Cancel booking
Check in/out
Branch Staff
Branch dashboard
View occupancy
Walk-in check-in
Check-out
View bookings
Admin
Network dashboard
Branch management
Resource management
Live occupancy
Basic analytics
Backend
Firestore
Firebase Auth
Storage
Security Rules
Emulator testing
29. Future Features
After MVP:
Phase 2
Push notifications.
QR-code check-in.
Booking reminders.
No-show detection.
Advanced analytics.
Export reports.
Phase 3
Payment integration.
Membership management.
IoT occupancy sensors.
Predictive demand analysis.
Dynamic pricing.
External calendar integration.
30. Non-Functional RequirementsPerformance
Dashboard should update near real-time.
Normal screens should load within a few seconds under normal network conditions.
Booking confirmation should happen without unnecessary refreshes.
Reliability
Booking conflicts must be prevented.
Firestore should be the authoritative source of booking state.
App should gracefully handle network failures.
Security
Firebase Authentication required for protected features.
Firestore Security Rules enforce authorization.
Users can only access permitted resources.
Scalability
The architecture should support:
10+ branches
   ↓
100+ branches
   ↓
1000+ resources
   ↓
10,000+ users
without requiring a complete architectural rewrite.
31. Success Metrics
The project can measure its success using:
Metric
Target
Double bookings
0
Branches represented centrally
100%
Real-time occupancy accuracy
>95%
Boking success rate
>98%
Wlk-ins recorded
>95%
Dshboard data freshness
Near real-time
Booking completion time
<1 minute
32. Acceptance Criteria
The MVP is considered successful when:
Booking
A user can select a branch, resource, date and time and successfully create a booking.
Double booking
Two users cannot successfully reserve the same desk/room for overlapping periods.
Occupancy
When a user checks in, the branch's current occupancy updates automatically.
Walk-in
Branch staff can register a walk-in user and assign an available resource.
Central visibility
An administrator can see occupancy across all branches from a single dashboard.
Security
A branch employee cannot modify another branch's resources or occupancy.
Analytics
The system stores sufficient historical booking/occupancy information to calculate utilization.
33. Recommended MVP Screen Map
Your Flutter app could have roughly these screens:

                    ┌──────────────┐
                    │ Splash       │
                    └──────┬───────┘
                           ↓
                    ┌──────────────┐
                    │ Login        │
                    └──────┬───────┘
                           ↓
                 ┌─────────┴─────────┐
                 ↓                   ↓
             Member             Staff/Admin
                 ↓                   ↓
          Member Dashboard      Dashboard
                 │                   │
       ┌─────────┼─────────┐    ┌────┼────┐
       ↓         ↓         ↓    ↓         ↓
   Branches   Bookings   Profile Branches Analytics
       │
       ↓
   Select Branch
       │
       ↓
   Select Resource
       │
       ↓
   Select Date/Time
       │
       ↓
   Confirm Booking
       │
       ↓
   My Booking
34. Recommended Tech Stack
I'd present your stack in the project documentation as:
Layer
Technology
Frontend
Flutter
Programming Language
Dart
Authentication
Firebase Authentication
Database
Cloud Firestore
File Storage
Firebase Storage
Server-side logic
Firebase Cloud Functions
Authorization
Firestore Security Rules
Notifications
Firebase Cloud Messaging
Local backend testing
Firebase Emulator Suite
Target devices
Android / iOS / Emulator
One important addition
Although your original stack is:
Dart + Flutter + Firebase Auth + Cloud Firestore + Firebase Storage + Emulator/Device
I'd add Firebase Cloud Functions to the architecture, particularly for booking conflict validation, privileged operations, and aggregation/analytics. It makes your solution much more defensible technically.

35. One-Line Product Definition
For your presentation/viva, you can summarize the entire project as:
Occupier is a centralized, real-time co-working space management platform that synchronizes bookings, walk-ins, and occupancy across multiple branches while providing management with reliable utilization analytics for operational and expansion decisions.

This gives you a strong connection between the problem → solution → features → architecture → business value, rather than making the project look like simply a "desk booking app."