# Occupancy Dashboard Requirements

## Central Admin Dashboard

The central admin dashboard provides a network-wide view of workspace
utilization across all branches.

### Metrics

- Total capacity
- Current occupied capacity
- Available capacity
- Overall occupancy percentage
- Number of today's desk bookings
- Number of today's meeting-room bookings
- Number of today's walk-ins

### Branch Overview

Each branch should display:

- Branch name
- Total capacity
- Current occupancy
- Available capacity
- Occupancy percentage

### Example

Network Occupancy:
1,284 / 1,850
69.4%

Branches:
- Jaipur: 82%
- Delhi: 74%
- Mumbai: 61%
- Bangalore: 87%

Today's Bookings:
- Desks: 623
- Meeting Rooms: 87
- Walk-ins: 42


## Branch Dashboard

Branch staff should see the current operational status of their branch.

### Metrics

- Current occupancy
- Total capacity
- Available capacity
- Occupancy percentage
- Available desks
- Occupied desks
- Available meeting rooms
- Occupied meeting rooms
- Today's bookings

### Booking Information

The dashboard should show upcoming bookings with:

- Time
- Resource
- Resource type
- Booking status


## Occupancy Rules

### Occupancy vs Booking

A booking represents a reservation.

An occupancy represents an actual check-in.

A resource is considered occupied only after the user checks in.

Therefore:

- Booked does not automatically mean occupied.
- Walk-ins can create occupancy without a booking.
- An active occupancy contributes to current occupancy.
- A completed occupancy does not contribute to current occupancy.


## Calculations

### Occupancy Rate

occupancy rate =
occupied capacity / total capacity × 100


### Available Capacity

available capacity =
total capacity - occupied capacity


### Network Occupancy

Network occupancy must be calculated using totals:

total occupied across branches /
total capacity across branches × 100

Individual branch percentages must not be averaged.


## Data Sources

The dashboard will eventually consume:

- Branch data
- Resource data
- Booking data
- Occupancy/check-in data

The occupancy data is the source of truth for current physical occupancy.