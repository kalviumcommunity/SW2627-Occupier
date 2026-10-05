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