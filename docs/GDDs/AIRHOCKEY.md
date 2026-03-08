# Air Hockey Game Design Document (GDD)

## Overview
Air Hockey is a 2-player competitive arcade game where players use paddles to hit a puck into the opposing player's goal. The game emphasizes fast-paced, physics-based action and precise controls.

## Core Mechanics

### 1. Match Flow & State
- **Player Count**: Exactly 2 players are required. The puck remains inactive (or hidden) until both players have joined and are assigned a paddle.
- **Winning Condition**: The first player to reach 11 goals wins the match.
- **Reset Sequence**: 
  - At the start of the game and immediately after each goal is scored, paddles are reset to their default starting positions (center of their respective halves).
  - The puck is reset to the exact center of the table.

### 2. The Field (Table)
- **Geometry**: The table is rectangular with rounded corners.
- **Boundaries**: 
  - The outer boundary is defined by line segments.
  - For simplicity and physics stability, the rounded corners are approximated by straight line segments placed every 15 degrees.
  - The long sides are solid, closed walls.
  - The short sides have a central "wall-free" segment acting as the goal.
- **Scoring**: A goal is registered when the puck travels completely past the goal line on a player's side.
- **Movement Constraints**: A player's paddle is strictly constrained to their own half of the table. It cannot cross the center line.

### 3. Controls
- **Input Method**: Paddle movement is controlled via 1:1 positional tracking using mouse movement or touch input. The paddle attempts to directly follow the cursor/finger position (bounded by maximum velocity and table constraints).

### 4. Physics & Collisions
- **Entity Shapes**:
  - Puck: Circle.
  - Paddles: Circles.
  - Walls: Line segments.
- **Collision Types**:
  - **Circle-to-Circle**: Used for paddle-hitting-puck interactions to transfer momentum and calculate bounce angles.
  - **Circle-to-Line Segment**: Used for puck/paddle collisions against the table walls and corners.
- **Cross-Platform Determinism**: 
  - To ensure the Lisp authoritative server and the JavaScript prediction client behave exactly the same way, floating-point math drift must be avoided.
  - All physics calculations (positions, velocities, distances, collision responses) will be computed using **fixed-point mathematics**. 
  - The precision scale will be configurable (e.g., using a constant scale factor of 1000 for `.000` precision).

## Technical Implementation
- **Lisp (Server)**:
  - Handles the authoritative fixed-point physics simulation, state management, and score tracking.
- **JavaScript (Client)**:
  - Mirrors the Lisp fixed-point physics engine for accurate client-side prediction.
  - Visuals are drawn using the HTML5 Canvas API.
  - Input translates pointer coordinates (`mousemove`, `touchmove`) into fixed-point targets sent to the server.