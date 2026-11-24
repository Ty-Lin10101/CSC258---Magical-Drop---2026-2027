################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Tyler Christopher Lin, 1011890296
# Student 2: Brandon Zento Li, 1011974035 
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       8
# - Unit height in pixels:      8
# - Display width in pixels:    256
# - Display height in pixels:   256
# - Base Address for Display:   0x10008000 ($gp)
##############################################################################

    .data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL:
    .word 0x10008000

DISPLAY_WIDTH: 
  .word 32

# Virtual game grid, where we have 14 rows * 7 cols * 4 bytes = 392 bytes + (6 rows * 7 cols * 4 bytes) = 560 TOTAL BYTES
# We allocate space for additional rows to account for overflow when throwing bubbles.
game_grid: .space 560  # got .space from https://jsevy.com/architecture/MIPSRef
GRAVITY_FLAGS: .space 560  # 1 byte per cell (0 = didn't move, 1 = moved by gravity)
PENDING_GRID: .space 560 # Kind of like gravity flagging, but this time we're checking for pending matches
MATCH_FLASH_DELAY: .word 200

# Boundary box offset -- top-left corner
START_X: .word 4 # starts 4 pixels from left of screen
START_Y: .word 4 # 4 pixels from top 
.eqv COLS 7
.eqv VISIBLE_ROWS 14
.eqv TOTAL_ROWS 20

# Player data 
PLAYER_OFFSET_X: .word 4
PLAYER_OFFSET_Y: .word 16


# The address of color constants.
COLOR_BLACK:    .word 0x000000     # Background color
COLOR_GRAY:     .word 0x808080     # Border color
COLOR_DARK_GRAY: .word 0x444444    # Player throw trace color
COLOR_LIGHT_GRAY: .word 0xCCCCCC   # Pending matches
COLOR_WHITE:    .word 0xffffff 
COLOR_RED:      .word 0xff0000
COLOR_GREEN:    .word 0x00ff00
COLOR_BLUE:     .word 0x0000ff
COLOR_YELLOW:   .word 0xffff00
BUBBLE_COLORS: .word 0xff0000, 0x00ff00, 0x0000ff, 0xffff00

# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:
    .word 0xffff0000

##############################################################################
# Mutable Data
##############################################################################

HELD_COLOR: .word 0        # 0 = empty hand
HELD_COUNT: .word 0
MAX_HOLD: .word 6

KEYSTROKE_COUNT: .word 0

FRAME_COUNT: .word 0 #one pass of the the game loop = 1 frame. Framce count = how many passes so far 

##############################################################################
# Code
##############################################################################
	.text
	.globl main

# --------------------------------------------------------------------------------------------------- MACROS

.macro PUSH_RA()
    addi $sp, $sp, -8 # reserve 2 words; only $ra is stored (at 4($sp)), 1 slot spare 
    sw $ra, 4($sp)
.end_macro

.macro POP_RA()
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra
.end_macro

# Cleans up the stack frame, but DOES NOT return (continues execution)
.macro POP_FRAME()
    lw $ra, 4($sp)
    addi $sp, $sp, 8  
.end_macro

# CELL_ADDR(dst, row, col, base): dst = address of game_grid cell (row, col); 7 x 20 
#   base = start of game_grid (la), row 0–19, col 0–6
# Purpose: check or change the game board's data  (grid row, grid col) 
.macro CELL_ADDR(%dst, %row, %col, %base)
    mul %dst, %row, COLS
    add %dst, %dst, %col
    sll %dst, %dst, 2
    add %dst, %dst, %base
.end_macro

# %dst = display address of unit (%row, %col): base + 4 * (row * width + col)
# %dst may equal %row, but must differ from %col, %width and %base
# dst = address of screen pixel (row, col); base = 0x10008000 (ADDR_DSPL), width = 32
# purpose: paint a pixel
# screen row, screen col
.macro SCREEN_ADDR(%dst, %row, %col, %width, %base)
    mul %dst, %row, %width
    add %dst, %dst, %col
    sll %dst, %dst, 2
    add %dst, %dst, %base
.end_macro

# --------------------------------------------------------------------------------------------------- MAIN

    # Run the game.
main:
  lw $t0, ADDR_DSPL       # $t0 = base address for display
  sw $zero, KEYSTROKE_COUNT
  
  jal draw_barrier
  li $s0, 5
start_rows:  # When game starts, add 5 rows to begin
  beqz $s0, start_rows_done
  jal add_bubble_row
  addi $s0, $s0, -1
  j start_rows
start_rows_done:
  jal draw_character
  jal draw_held_bubbles
  
  # Initialize the game
  j game_loop
  


# --------------------------------------------------------------------------------------------------- GAME LOOP

game_loop:
  lw $t0, ADDR_KBRD
    # Check if key has been pressed
  lw $t1, 0($t0)
    # Check which key has been pressed
  beqz $t1, sleep   # If no input, sleep and restart loop
  lw $t2 4($t0)  # load input's ASCII code

  li $a0, -1
  beq $t2, 0x61, is_valid_key
  li $a0, 1
  beq $t2, 0x64, is_valid_key  # if ASCII = 'd', move player with parameter $a0 = 1 (move right)
  beq $t2, 0x73, is_valid_key  # if ASCII = 's', grab bubble
  beq $t2, 0x77, is_valid_key  # if ASCII = 'w', check if can throw anything
  
  beq $t2, 0x70, pause         # if ASCII = 'p', quit game
  
  beq $t2, 0x71, quit         # if ASCII = 'q', quit game
  j sleep

 is_valid_key:
  # Increment Keystroke Counter
  lw $t4, KEYSTROKE_COUNT
  addi $t4, $t4, 1
  sw $t4, KEYSTROKE_COUNT

  # Check if we hit 15 keystrokes
  li $t5, 15
  blt $t4, $t5, execute_action # If < 15, just do the action

  # Hit 15, reset counter and push a row
  
  # SAVE $t2 AND $a0 BEFORE CALLING add_bubble_row
  addi $sp, $sp, -8
  sw $t2, 0($sp)               # Save ASCII code
  sw $a0, 4($sp)               # Save direction parameter

  sw $zero, KEYSTROKE_COUNT
  jal add_bubble_row           # This pushes the new row down!

  # RESTORE $t2 AND $a0 
  lw $t2, 0($sp)
  lw $a0, 4($sp)
  addi $sp, $sp, 8

execute_action:
  # Now execute the original key action (a/d/s/w)
  li $a0, -1 
  beq $t2, 0x61, do_move
  li $a0, 1
  beq $t2, 0x64, do_move
  beq $t2, 0x73, do_grab
  beq $t2, 0x77, do_throw
  
  j sleep

sleep:
   # Timer in here since sleep always runs, count frames in sleep 
   lw $t0, FRAME_COUNT
   addi $t0, $t0, 1
   sw $t0, FRAME_COUNT
   
   blt $t0, 300, timer_done #300, 300 * 16ms = 4800ms which would be approx 5000 ms,accounting for slight delays 
   sw $zero, FRAME_COUNT
   jal add_bubble_row
   
 timer_done: #timer section done, we don't add a bubble row unless its been 5 seconds 
   
   # Re-paint the screen 
  jal draw_grid
  jal draw_character
  jal draw_held_bubbles

  li $v0, 32                    # sleep syscall
  li $a0, 16                    # ~16 ms  ---> now 250ms = 0.25s,  CHANGE THIS LATER
  syscall
  j game_loop

pause:
  lw $a0, COLOR_WHITE
  jal draw_pause_bars
  
pause_loop:
  li $v0, 32
  li $a0, 16
  syscall
  
  lw $t0, ADDR_KBRD # remember, t0 just stores where the address is 
  lw $t1, 0($t0) #flag at the keyboard address: 1 = a key was pressed   

  beqz $t1, pause_loop #if no key was pressed, stay paused 
  
  lw $t2, 4($t0)  
  
  beq $t2, 0x70, resume #resume: back to repainting the screen and game loop
  beq $t2, 0x71, quit         # if ASCII = 'q', quit game
  
  j pause_loop
  
resume: 
  lw $a0, COLOR_BLACK 
  jal draw_pause_bars #erase the pause bars 
  j sleep 
    
    

# Exit program gracefully when done
quit:
  li $v0, 10                  # System call for graceful exit
  syscall

# --------------------------------------------------------------------------------------------------- GAME OVER 

game_over:
  # Draw a giant white X over the screen to indicate game over
  lw $t0, ADDR_DSPL
  li $t1, 0
  li $t2, 32
  mul $t2, $t2, $t2       # 32 * 32 = 1024 total pixels
  lw $t3, COLOR_WHITE

game_over_loop:
  bge $t1, $t2, wait_for_quit
  sll $t4, $t1, 2
  add $t4, $t0, $t4
  sw $t3, 0($t4)
  addi $t1, $t1, 1
  j game_over_loop

wait_for_quit:
  lw $t0, ADDR_KBRD
  lw $t1, 0($t0)
  beqz $t1, game_over_sleep
  lw $t2, 4($t0)
  beq $t2, 0x71, quit     # Wait for 'q' to quit
  j game_over

game_over_sleep:
  li $v0, 32
  li $a0, 16
  syscall
  j game_over

# --------------------------------------------------------------------------------------------------- DRAWING GAME BOUNDARY

draw_barrier:
    lw $t0, ADDR_DSPL
    lw $s3, DISPLAY_WIDTH
    lw $s4, START_X
    lw $s5, START_Y 
    
    li $t2, 0                      # $t2 = row counter

draw_barrier_row_loop:
  bge $t2, 16, draw_barrier_end
  li $t3, 0                        # $t3 = col counter
  
draw_barrier_col_loop:
  bge $t3, 9, draw_next_row

  beq $t2, 0, is_wall
  li $t6, 15
  beq $t2, $t6, is_wall
  beq $t3, 0, is_wall
  li $t6, 8
  beq $t3, $t6, is_wall

  lw $v1, COLOR_BLACK
  j calculate_address

is_wall:
  lw $v1, COLOR_GRAY

calculate_address:
  add $t4, $t2, $s5               # $t4 = row + START_Y
  add $t5, $t3, $s4               # $t5 = col + START_X

  # Row Address Calculation
  # Offset = 4 * (Global Row * DISPLAY_WIDTH + Global Col)
  SCREEN_ADDR($t8, $t4, $t5, $s3, $t0)   # $t8 = exact memory address

  # Paint the pixel
  sw $v1, 0($t8)

  # col counter increment
  addi $t3, $t3, 1
  j draw_barrier_col_loop

    
draw_next_row:
  # row counter increment
  addi $t2, $t2, 1
  j draw_barrier_row_loop

draw_barrier_end:
  jr $ra


# --------------------------------------------------------------------------------------------------- DRAWING PLAYER 

draw_character:
  PUSH_RA()
  
  jal get_player_address
  move $t8, $v0
    
  # paint character
  lw $v1, COLOR_WHITE
  sw $v1, 0($t8)

  jal draw_trajectory      

  POP_RA()

erase_character:
  PUSH_RA()
  
  jal get_player_address
  move $t4, $v0
  
  sw $zero, 0($t4)              # $zero = 0 = black
  jal erase_trajectory
  
  POP_RA()

# Paints every held slot with the color in $a1 (0 = erase). Preserves $s0-$s2.
paint_held_bubbles:
  addi $sp, $sp, -16
  sw   $ra, 0($sp)
  sw   $s0, 4($sp)              # counter
  sw   $s1, 8($sp)              # bound (HELD_COUNT)
  sw   $s2, 12($sp)             # color
  move $s2, $a1
  lw   $s1, HELD_COUNT
  li   $s0, 0
paint_held_loop:
  bge  $s0, $s1, paint_held_done
  move $a0, $s0
  jal  get_held_address
  sw   $s2, 0($v0)
  addi $s0, $s0, 1
  j    paint_held_loop
paint_held_done:
  lw   $ra, 0($sp)
  lw   $s0, 4($sp)
  lw   $s1, 8($sp)
  lw   $s2, 12($sp)
  addi $sp, $sp, 16
  jr   $ra

# Both of these tail-jump, so paint_held_bubbles returns straight to the caller.
erase_held_bubbles:
  li   $a1, 0
  j    paint_held_bubbles

draw_held_bubbles:              # all held bubbles share HELD_COLOR
  lw   $a1, HELD_COLOR
  j    paint_held_bubbles
  

# $a0 = slot index (0 = nearest player). Returns address in $v0.
get_held_address:
  lw   $t8, START_Y
  lw   $t0, PLAYER_OFFSET_Y
  add  $t8, $t8, $t0
  addi $t8, $t8, 1
  add  $t8, $t8, $a0             # screen row (slot below the player)
  lw   $t9, START_X
  lw   $t0, PLAYER_OFFSET_X
  add  $t9, $t9, $t0             # screen col
  lw   $t0, DISPLAY_WIDTH
  lw   $v0, ADDR_DSPL
  SCREEN_ADDR($t8, $t8, $t9, $t0, $v0)
  move $v0, $t8
  jr   $ra


  
# --------------------------------------------------------------------------------------------------- DRAWING PLAYER TRAJECTORY
  
draw_trajectory:
  lw $t0, ADDR_DSPL             # Base display address
  lw $s3, DISPLAY_WIDTH         # Screen width (64)
  lw $s4, START_X               # Barrier start X
  lw $s5, START_Y               # Barrier start Y
  # Determine the X column (same column as the player)
  lw $t1, PLAYER_OFFSET_X  
  add $t5, $s4, $t1             # $t5 = Global X coordinate of the player/line
  addi $t1, $t1, -1             # $t1 = grid column (player X - 1)
  
  # Determine the starting Y row (two rows above the player)
  lw $t2, PLAYER_OFFSET_Y       
  add $t4, $s5, $t2             
  addi $t4, $t4, -2             # $t4 = row counter (going up)
  
  # Define stopping point at the top (right under the top wall, top row = $s6 = START_Y + 1)
  addi $s6, $s5, 1

trajectory_loop:
  blt $t4, $s6, trajectory_end  # Checks if top boundary is reached

  sub $t6, $t4, $s5             # local_row = global_row - START_Y
  addi $t6, $t6, -1

  la $t9, game_grid
  CELL_ADDR($t8, $t6, $t1, $t9)
  lw $t9, 0($t8)               # Read grid cell
  # Stop if cell is not 0 (black) -> a bubble or border is there
  bnez $t9, trajectory_end

  
  andi $t7, $t4, 1              # Check if row is even or odd. RECALL: $t4 = row counter
  bnez $t7, skip_dash_pixel     # If odd, skip painting (leaves it black)

  # Row-Major Address Calculation for current pixel on screen
  SCREEN_ADDR($t8, $t4, $t5, $s3, $t0)   # $t8 = exact memory address

  # Paint the dark grey pixel
  lw $v1, COLOR_DARK_GRAY
  sw $v1, 0($t8)
    
skip_dash_pixel:
  addi $t4, $t4, -1             # Move one row higher
  j trajectory_loop

trajectory_end:
  jr $ra


erase_trajectory:               # repaints only the player's current column
  lw $t0, ADDR_DSPL
  lw $t3, DISPLAY_WIDTH
  lw $t4, START_X
  lw $t5, START_Y
  lw $t1, PLAYER_OFFSET_X       # player's local column (1 to 7)
  add $t9, $t4, $t1             # screen column
  addi $t1, $t1, -1             # $t1 = grid column (player X - 1)
  la $t6, game_grid
  li $t2, 0                     # grid row 0 to 13

erase_loop:
  bge $t2, 14, erase_done
  CELL_ADDR($t7, $t2, $t1, $t6)
  lw $v1, 0($t7)                # color from grid (0 if empty)

  add $t8, $t2, $t5
  addi $t8, $t8, 1              # screen row = START_Y + 1 + row
  SCREEN_ADDR($t8, $t8, $t9, $t3, $t0)
  sw $v1, 0($t8)

  addi $t2, $t2, 1
  j erase_loop

erase_done:
  jr $ra

  
# --------------------------------------------------------------------------------------------------- DRAWING BUBBLES

# shift everything down, fill a new top row, repaint
add_bubble_row:
  PUSH_RA()     
  # these functions override $ra after returning
  jal shift_grid_down
  jal fill_top_row
  jal draw_grid

  POP_RA()

# grid[i] = grid[i-7] for i = 97 down to 7
# (counting downward so we never overwrite a row before copying it)
shift_grid_down:
  la $t0, game_grid
  li $t1, 104                    # start at end of row 14 (row x 7 + col(6 is last)) 

shift_loop:
  blt $t1, 7, check_overflow    # done shifting: check for game over
  sll $t2, $t1, 2
  add $t2, $t0, $t2             # $t2 = &grid[i]
  lw $t3, -28($t2)              # grid[i - 7] (copying the cell directly above) (28 = 7 * 4)
  sw $t3, 0($t2)                # store that colour into the current cell 
  addi $t1, $t1, -1          
  j shift_loop

# Game over if anything sits in row 14 (indices 98-104). Used after adding a row and after a throw.
check_overflow:
  la   $t0, game_grid
  li   $t1, 98 # row 14 = indicies 98-104 (game board is rows 0-13, 14th is the spare below) 
check_loop:
  bgt  $t1, 104, no_game_over
  sll  $t2, $t1, 2
  add  $t2, $t0, $t2            #$t2 = address of grid[i] 
  lw   $t3, 0($t2)              
  bnez $t3, game_over           # bubble pushed off the board --> game_over never returns
  addi $t1, $t1, 1              
  j    check_loop
no_game_over:
  jr   $ra

# fill row 0 of the grid with random colors
fill_top_row:
  la $t0, game_grid
  la $t4, BUBBLE_COLORS
  li $t1, 0                     # column counter

fill_loop:
  bge $t1, 7, fill_done
  li $v0, 42                    # syscall 42: random int in [0, $a1)
  li $a0, 0                     # default generator
  li $a1, 4                     # 4 colors (from our list, BUBBLE_COLORS)
  syscall                       # $a0 = random 0..3 
  
  sll $a0, $a0, 2               # x 4 byte offset into colour list 
  add $a0, $t4, $a0             # address of BUBBLE_COLORS[r]
  lw $t5, 0($a0)                # chosen color
  
  sll $t2, $t1, 2               # back to the current col, byte offset into row 0               
  add $t2, $t0, $t2
  sw $t5, 0($t2)                # grid[0][col] = color
  addi $t1, $t1, 1
  j fill_loop

fill_done:
  jr $ra                        #return to add_bubble_row

# paint the whole grid onto the display
draw_grid:
  lw $t0, ADDR_DSPL
  lw $t3, DISPLAY_WIDTH
  lw $t4, START_X
  addi $t4, $t4, 1              # interior left column
  lw $t5, START_Y
  addi $t5, $t5, 1              # interior top row
  la $t6, game_grid
  li $t1, 0                     # row counter

draw_grid_row:
  bge $t1, 14, draw_grid_done
  li $t2, 0                     # col counter

draw_grid_col:
  bge $t2, 7, draw_grid_next_row
  CELL_ADDR($t7, $t1, $t2, $t6)
  lw $v1, 0($t7)                # color from grid

  add $t8, $t1, $t5             # screen row
  add $t9, $t2, $t4             # screen col
  SCREEN_ADDR($t8, $t8, $t9, $t3, $t0)
  sw $v1, 0($t8)

  addi $t2, $t2, 1
  j draw_grid_col

draw_grid_next_row:
  addi $t1, $t1, 1
  j draw_grid_row

draw_grid_done:
  jr $ra
  
  
# --------------------------------------------------------------------------------------------------- PAUSE BARS
#drawing the pause bars from (8, 18) to (15, 23) 
draw_pause_bars:
  lw $t0, ADDR_DSPL
  lw $t1, DISPLAY_WIDTH
  li $t2, 8 # row counter
pause_bars_row:
  bge $t2, 16, pause_bars_done
  
  li $t3, 18 #col counter

pause_bars_col:
  bge $t3, 24, pause_bars_next_row 
  beq $t3, 20, pause_bars_next_col 
  beq $t3, 21, pause_bars_next_col
  
  
  # (%dst, %row, %col, %width, %base)
  SCREEN_ADDR($t9, $t2, $t3, $t1, $t0)
  sw $a0, 0($t9) 
  
pause_bars_next_col:
  addi $t3, $t3, 1 #next col 
  j pause_bars_col 
  
pause_bars_next_row: 
  addi $t2, $t2, 1 # next row   
  j pause_bars_row 
  

pause_bars_done:
  jr $ra 

  

# --------------------------------------------------------------------------------------------------- PLAYER CONTROLS

do_move:
  jal move_player
  j sleep
  
move_player:
  PUSH_RA()

  lw $t3, PLAYER_OFFSET_X
  add $s1, $t3, $a0   # $s1 = new X position
  blt $s1, 1, move_done  # left wall collision -- ignore movement
  bgt $s1, 7, move_done  # right wall collision -- ignore movement

  jal erase_character
  jal erase_held_bubbles       # old column's held pixels
  sw  $s1, PLAYER_OFFSET_X
  jal draw_character
  jal draw_held_bubbles

move_done:
  POP_FRAME()
  jr $ra

# ----------------------------------------------------------- GRAB

do_grab:
  jal grab_bubble
  j sleep

find_lowest_bubble_in_col:
  la $t0, game_grid
  lw $t1, PLAYER_OFFSET_X
  addi $t1, $t1, -1            # col = X − 1  (grid column)
  li  $t2, 13                  # start at bottom row

find_loop:
  bltz $t2, find_none           
  CELL_ADDR($t3, $t2, $t1, $t0)# &t3 = address of grid[row][col]
  lw  $t4, 0($t3)              # cell color
  bnez $t4, find_hit           # non-zero → found
  addi $t2, $t2, -1            # else move up one row
  j find_loop

find_hit:
  move $v0, $t4                # color
  move $v1, $t2                # grid row
  li   $t0, 1                  # found flag
  jr   $ra

find_none:
  li  $v0, 0
  li  $v1, -1                  # row = −1 signals "nothing to grab"
  li  $t0, 0
  jr   $ra

grab_bubble:
  PUSH_RA()

grab_loop:
  # Save our current held state before calling the finder
  lw $s0, HELD_COUNT
  lw $s1, HELD_COLOR
  
  jal find_lowest_bubble_in_col
  beqz $t0, grab_done          # Empty column --> stop. $t0 stores whether something was found or not 

  # Capacity check
  lw $t7, MAX_HOLD
  bge $s0, $t7, grab_done      # Hand full (HELD_COUNT >= MAX_HOLD) --> stop

  # Color check
  beqz $s0, grab_accept        # Hand empty --> Accept (first colour can be anything) 
  bne $s1, $v0, grab_done      # Different color --> Stop grabbing

grab_accept:
  # Save new state
  sw $v0, HELD_COLOR
  addi $s0, $s0, 1
  sw $s0, HELD_COUNT

  # Clear the bubble's cell from the grid
  lw   $t1, PLAYER_OFFSET_X
  addi $t1, $t1, -1            # grid col
  la   $t3, game_grid
  CELL_ADDR($t2, $v1, $t1, $t3)  # $v1 is the row returned by the finder
  sw   $zero, 0($t2)

  # Loop back to grab the next one!
  j grab_loop

grab_done:
  # Only redraw if we actually grabbed something
  lw $t0, HELD_COUNT
  beqz $t0, grab_exit

  jal  draw_grid
  jal  draw_character
  jal  draw_held_bubbles

grab_exit:
  POP_RA()

# ----------------------------------------------------------- THROW LOGIC
  
do_throw:
  jal check_throw
  j sleep

check_throw:
  PUSH_RA()

  lw   $t0, HELD_COUNT
  beqz $t0, throw_done         # If hands are empty, do nothing

  lw   $t6, PLAYER_OFFSET_X   
  addi $t6, $t6, -1            # grid column (0-6), col = X - 1   
  la   $t7, game_grid
  li   $t1, 13

find_landing_spot:
  bltz $t1, throw_empty_col #past the top --> empty column 
  CELL_ADDR($t2, $t1, $t6, $t7) # address of grid[row][col]
  lw   $t3, 0($t2)          # what is at grid[row][col]
  bnez $t3, throw_at_place  # Hit a bubble, land here

  addi $t1, $t1, -1         # Move up
  j find_landing_spot

throw_at_place:
  addi $t1, $t1, 1          # Start placing BELOW the bubble we hit
  j throw_loop_start

throw_empty_col:
  li $t1, 0                 # Empty column, start at top

throw_loop_start:
  lw   $t0, HELD_COUNT
  lw   $t5, HELD_COLOR
  li   $t4, 0               # Loop counter

throw_place_loop:
  bge  $t4, $t0, throw_check_matches # i >= HELD_COUNT --> check for matches
  bgt  $t1, 19, throw_check_matches 

  CELL_ADDR($t2, $t1, $t6, $t7) #remember, t7 stores game_grid starting address
  sw   $t5, 0($t2)          # Placed a bubble at (row, col)

  # flag this cell as "moved" so the first match pass sees it （marking this cell in GRAVITY_FLAGS = 1) 
  mul  $t8, $t1, 7 
  add  $t8, $t8, $t6  #index = row x 7 + col 
  la   $t9, GRAVITY_FLAGS
  add  $t9, $t9, $t8  #address = GRAVITY_FLAGS = index
  li   $t8, 1
  sb   $t8, 0($t9)  #store 1 BYTE  

  addi $t1, $t1, 1          # Move down for the next bubble
  addi $t4, $t4, 1          # one more has been placed
  j throw_place_loop


throw_check_matches:        #deals with matches created by the throw, along with throw_cascade_loop
  # ERASE THE HELD BUBBLES IMMEDIATELY AFTER THROWING
  jal erase_held_bubbles
  
  lw $s6, PLAYER_OFFSET_X
  addi $s6, $s6, -1            # s6 = target column 
  lw $s7, HELD_COLOR           # s7 = target color

  li $s3, 1                    # $s3 = 1 (flag): this is the initial throw)

throw_cascade_loop:            
  move $a0, $s6                # input: which column  (1st time: mine; later: −1)
  move $a1, $s7                # input: which colour  (1st time: mine; later: 0)
  move $a2, $s3                # Pass the first-throw flag to the checker
  
  jal check_vertical_matches   # find triggers → flood_mark paints them GRAY in game_grid
  beqz $v0, throw_cascade_done # If nothing cleared, we're done
  
  li $s3, 0                    # Any subsequent checks are gravity cascades

  # flash the highlighted bubbles
  jal draw_grid                # repaint grid (shows COLOR_LIGHT_GRAY cells)
  jal draw_character           # keep player visible

  li $v0, 32                   # sleep syscall
  lw $a0, MATCH_FLASH_DELAY    # pause for 200ms so the player sees the highlight
  syscall                       

  # now remove them
  jal clear_pending            # set marked cells to black, reset flags
  
  # Clear the GRAVITY_FLAGS array before applying gravity
  la $t0, GRAVITY_FLAGS 
  li $t1, 0
clear_flags:
  bge $t1, 560, flags_cleared
  sw $zero, 0($t0)
  addi $t0, $t0, 4
  addi $t1, $t1, 4
  j clear_flags
flags_cleared:

  jal apply_gravity #now the gravity flags checks what was moved after the clear, not the throw
  
  # After the first check, scan all columns and match any color (not just target col and colour)
  li $s6, -1                   # Scan ALL columns
  li $s7, 0                    # 0 means "match any color"
  j throw_cascade_loop
  
throw_cascade_done:
  # erase first while HELD_COUNT is still > 0 (erase_held_bubbles uses HELD_COUNT to know how many to erase)
  jal erase_held_bubbles

  # clear the hand state
  sw $zero, HELD_COLOR
  sw $zero, HELD_COUNT

  # Redraw everything
  jal draw_grid
  jal draw_character

  # Check for overflow game over
  jal check_overflow

throw_done: 
  POP_RA()

# ----------------------------------------------------------- MATCHING LOGIC
#Target column and colour = where could a NEW match possibly be? 
#Right after a throw → only your column and colour.
#After gravity → anywhere, any colour.(hence no target colour, and check all columns)
#The match itself is always "3 of the same colour as each other."


# $a0 = target column (0-6), or -1 for all columns
# $a1 = target color (0 for any color)
# $a2 = is_first_throw (1 = yes, 0 = no, only check gravity flags)
check_vertical_matches:
  PUSH_RA()
  li $s4, 0                  # $s4 = found flag (0 = none, 1 = cleared)
  
  move $s0, $a0              # $s0 = target column (-1 means check all columns)
  move $s1, $a1              # $s1 = target color (0 means any colour) 
  move $s5, $a2              # $s5 = is_first_throw
  
  li $t1, 0                  # row

cvm_row_loop:
  bge $t1, 14, cvm_done      # Only scan visible grid (0-13)

  # Set up column loop
  # If s0 == -1, check all columns (0 to 6). Otherwise, just check s0.
  li $t2, 0                  # col counter
  bltz $s0, cvm_col_loop_start # -1 --> check every col 
  move $t2, $s0              # Start at target col
  
cvm_col_loop_start:
  # Fall through to check this column

cvm_check_col: #check one cell 
  # Calculate address of (row, col)
  la $t3, game_grid
  CELL_ADDR($t4, $t1, $t2, $t3)   # $t4 = grid[row][col]
  lw $t5, 0($t4)              
  beqz $t5, cvm_next_col     # If empty, skip
  
  # Color check (if s1 != 0)
  beqz $s1, cvm_check_match # any colour mode 
  bne $t5, $s1, cvm_next_col #not the target colour, falls into Piece 4

cvm_check_match:
  # Check row + 1 (below it)
  lw $t9, 28($t4)            # cell below (next row = +7 words)
  bne $t9, $t5, cvm_next_col # not the same as me, next cell
  lw $t9, 56($t4)            # two below (14 * 4) 
  bne $t9, $t5, cvm_next_col 

  # CHECK GRAVITY FLAGS — a match only counts if one of the 3 bubbles
  # was moved (by gravity, or by the throw itself)
  j cvm_check_flags

cvm_trigger:
  # found vertical trigger
  li $s4, 1
  move $s2, $t5
  move $a0, $t1               #start flood mark at current row
  move $a1, $t2               #current col 

  # Save loop registers (row, col, found) 
  addi $sp, $sp, -12
  sw   $t1, 0($sp)
  sw   $t2, 4($sp)
  sw   $s4, 8($sp)

  jal flood_mark             # highlights and doesn't clear

  lw   $t1, 0($sp)      #get row, col and found back 
  lw   $t2, 4($sp)
  lw   $s4, 8($sp)
  addi $sp, $sp, 12
  j cvm_next_col

cvm_check_flags:
  # Check if AT LEAST ONE of the 3 stacked bubbles was moved by gravity
  la   $t7, GRAVITY_FLAGS
  mul  $t3, $t1, 7           # row * 7
  add  $t3, $t3, $t2         # add the col 
  add  $t3, $t7, $t3         # $t3 = GRAVITY_FLAGS[row][col] (starting address of GRAVITY flags + index)

  lb   $t9, 0($t3)           # this cell
  bnez $t9, cvm_trigger      # 1 --> moved 
  lb   $t9, 7($t3)           # cell below (row + 1) 
  bnez $t9, cvm_trigger
  lb   $t9, 14($t3)          # two below (row + 2)
  bnez $t9, cvm_trigger

  j cvm_next_col

cvm_next_col:
  # If we are checking a specific column, move to the next row
  bgez $s0, cvm_next_row
  
  # If we are checking all columns, move to the next column
  addi $t2, $t2, 1
  blt $t2, 7, cvm_check_col

cvm_next_row:
  addi $t1, $t1, 1
  li $t2, 0   # Reset column back to 0
  j cvm_row_loop

cvm_done:
  move $v0, $s4 # return found (0 or 1) 
  POP_RA()
  
flood_mark:
  PUSH_RA() #recursion, save MY current address 
  
  # Save $a0, $a1, $s2, $s4 so they aren't destroyed by recursion
  addi $sp, $sp, -16
  sw $a0, 0($sp)  #MY row
  sw $a1, 4($sp)  #MY col (saved row and col so when we recurse on neighbours, we know who the neighbours are)
  sw $s2, 8($sp)  #the target colour (what was matched, so the subcalls know what to check against)
  sw $s4, 12($sp) #(a counter the caller uses) 
  
  # BASE CASE 1: Bounds check (off the board)  -------------------------------------
  bltz $a0, ff_done #row < 0
  bge $a0, 20, ff_done #row >= 20 (ACCOUNTS FOR OVERFLOW)
      # game_grid: visible board is 7 cols × 14 rows (rows 0–13).
      # Rows 14–19 are spare: a full-hand throw (MAX_HOLD = 6) can land up to 6 rows
      # past the board before matching / check_overflow runs.
  bltz $a1, ff_done #col < 0
  bge $a1, 7, ff_done #col >= 7 
  
  # BASE CASE 2: Check cell (not the target colour?) -------------------------------------
  la $t0, game_grid
  CELL_ADDR($t1, $a0, $a1, $t0)
  lw $t2, 0($t1)
  
  bne $t2, $s2, ff_done      # If not matching color, stop

  # BASE CASE 3:  Already marked? stop (prevents infinite recursion)  -------------------------------------
  mul $t3, $a0, 7
  add $t3, $t3, $a1         # index = row x 7 + col
  la  $t4, PENDING_GRID     
  add $t4, $t4, $t3        # address of the cell's flag 
  lb  $t5, 0($t4)         
  bnez $t5, ff_done        #t5 = the flag = 1? then STOP 

  # Mark it as pending
  li  $t5, 1
  sb  $t5, 0($t4) 

  # Highlight it light gray so the player sees the match
  lw  $t5, COLOR_LIGHT_GRAY
  sw  $t5, 0($t1) 
  
  #Spread to the neighbours: up down left right 
  
  # Recurse Up
  lw $a0, 0($sp)  #MY row (reload this, since last call may have changed $a0) (read back from Stack frame)
  lw $a1, 4($sp)  #MY col 
  addi $a0, $a0, -1 #call on row above
  jal flood_mark
  
  # Recurse Down
  lw $a0, 0($sp)
  lw $a1, 4($sp)
  addi $a0, $a0, 1
  jal flood_mark
  
  # Recurse Left
  lw $a0, 0($sp)
  lw $a1, 4($sp)
  addi $a1, $a1, -1
  jal flood_mark
  
  # Recurse Right
  lw $a0, 0($sp)
  lw $a1, 4($sp)
  addi $a1, $a1, 1 
  jal flood_mark

ff_done:
  # Restore $s2 and $s4, fufilling contract (s2 is target colour, s4 is match checker's counter ) 
  lw $s2, 8($sp) 
  lw $s4, 12($sp)
  addi $sp, $sp, 16
  
  POP_RA()

# Clear every grid cell that flood_mark flagged as pending, and reset the flags.
# Grid becomes black at those cells; caller must redraw and run gravity.
clear_pending:
  la  $t0, game_grid     #pointer for grid
  la  $t1, PENDING_GRID  #pointer for the marks
  li  $t2, 0
clear_pending_loop:
  bge $t2, 140, clear_pending_done    # 20 rows * 7 cols
  lb  $t3, 0($t1)                     #current cell's mark
  beqz $t3, cp_skip                   #not marked --> leave it
  sw  $zero, 0($t0)                   # clear grid cell to black
  sb  $zero, 0($t1)                   # reset pending flag
cp_skip:
  addi $t0, $t0, 4                    #next grid cell 
  addi $t1, $t1, 1                    #next mark
  addi $t2, $t2, 1
  j    clear_pending_loop
clear_pending_done:
  jr   $ra

# ----------------------------------------------------------- GRAVITY

apply_gravity:
  addi $sp, $sp, -8
  sw   $ra, 4($sp)
  sw   $s0, 0($sp)

  la   $s0, game_grid         
  li   $t1, 0                  # col = 0

gravity_col_loop:
  bge  $t1, 7, gravity_done

  li   $t2, 0                 # read_row (start from top)
  li   $t3, 0                 # write_row

gravity_row_loop:
  bge $t2, 20, gravity_next_col #all 20 rows read, go next colx1

  # Read cell at (read_row, col)
  CELL_ADDR($t5, $t2, $t1, $s0)
  lw   $t6, 0($t5)  #current bubble

  beqz $t6, gravity_skip       # If empty, skip

  # Move to write_row
  CELL_ADDR($t5, $t3, $t1, $s0)
  sw   $t6, 0($t5)  #store bubble in write row

  # Only clear the original cell if it actually moved
  beq  $t2, $t3, gravity_no_move  #read = write --> it didn't move 
  
  # if reached this point, the bubble moved
  
  # Clear read_row properly!
  mul  $t4, $t2, 7
  add  $t4, $t4, $t1  
  sll  $t4, $t4, 2
  add  $t5, $s0, $t4   # address of (read_row, col) 
  sw   $zero, 0($t5)   # grid[read_row][col] is cleared now

  # Set the gravity flag at the new write_row
  mul  $t4, $t3, 7
  add  $t4, $t4, $t1  #index of (write_row, col) 
  la   $t5, GRAVITY_FLAGS
  add  $t5, $t5, $t4  
  li   $t6, 1    
  sb   $t6, 0($t5)  #flag = 1 so it means that this bubble moved
  
gravity_no_move:
  addi $t3, $t3, 1            # Move write_row down (spot is now filled)

gravity_skip:
  addi $t2, $t2, 1            # Move read_row down
  j gravity_row_loop

gravity_next_col:
  addi $t1, $t1, 1
  j gravity_col_loop

gravity_done:
  lw   $s0, 0($sp)    
  lw   $ra, 4($sp)
  addi $sp, $sp, 8
  jr   $ra
  
# --------------------------------------------------------------------------------------------------- HELPER(S)
get_player_address:
  lw $t0, ADDR_DSPL
  lw $t1, DISPLAY_WIDTH
  lw $t2, START_Y
  lw $t3, PLAYER_OFFSET_Y
  add $t2, $t2, $t3            # global row
  lw $t3, START_X
  lw $t4, PLAYER_OFFSET_X
  add $t3, $t3, $t4            # global col
  SCREEN_ADDR($v0, $t2, $t3, $t1, $t0)
  jr $ra
