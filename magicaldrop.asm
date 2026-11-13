################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Tyler Christopher Lin, 1011890296
# Student 2: Name, Student Number (if applicable)
#
# We assert that the code submitted here is entirely our own 
# creation, and will indicate otherwise when it is not.
#
######################## Bitmap Display Configuration ########################
# - Unit width in pixels:       TODO
# - Unit height in pixels:      TODO
# - Display width in pixels:    TODO
# - Display height in pixels:   TODO
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


game_grid: .space 392  # got .space from https://jsevy.com/architecture/MIPSRef

# Boundary box offset -- top-left corner
START_X: .word 4
START_Y: .word 4

# Player data 
PLAYER_OFFSET_X: .word 4
PLAYER_OFFSET_Y: .word 16


# The address of color constants.
COLOR_BLACK:    .word 0x000000     # Background color
COLOR_GRAY:     .word 0x808080     # Border color
COLOR_DARK_GRAY: .word 0x444444    # Player throw trace color
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

##############################################################################
# Code
##############################################################################
	.text
	.globl main


    # Run the game.
main:
  lw $t0, ADDR_DSPL       # $t0 = base address for display
  
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
    # 1a. Check if key has been pressed
  lw $t1, 0($t0)
    # 1b. Check which key has been pressed
  beqz $t1, sleep   # If no input, sleep and restart loop
  lw $t2 4($t0)  # load input's ASCII code

  li $a0, -1 
  beq $t2, 0x61, do_move  # if ASCII = 'a', move player with parameter $a0 = -1 (move left)
  li $a0, 1
  beq $t2, 0x64, do_move  # if ASCII = 'd', move player with parameter $a0 = 1 (move right)
  beq $t2, 0x73, do_grab  # if ASCII = 's', grab bubble
  # beq $t2, 0x77, check_throw  # if ASCII = 'w', check if can throw anything
  
  beq $t2, 0x71, quit         # if ASCII = 'q', quit game
  j sleep
  
    # 2a. Check for collisions
	# 2b. Update locations (capsules)
	# 3. Draw the screen
    # 4. Sleep

  # 5. Go back to Step 1
  j game_loop

sleep:
  li $v0, 32                    # sleep syscall
  li $a0, 16                    # ~16 ms
  syscall
  j game_loop

# Exit program gracefully when done
quit:
  li $v0, 10                  # System call for graceful exit
  syscall


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
  mul $t7, $t4, $s3             # Global Row * DISPLAY_WIDTH
  add $t7, $t7, $t5             # + Global Col
  sll $t7, $t7, 2               # Multiply by 4 bytes per unit
  add $t8, $t0, $t7             # $t8 = exact memory address

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
  addi $sp, $sp, -4
  sw $ra, 0($sp)
  
  jal get_player_address
  move $t8, $v0
    
  # paint character
  lw $v1, COLOR_WHITE
  sw $v1, 0($t8)

  jal draw_trajectory      

  lw $ra, 0($sp)
  addi $sp, $sp, 4
  jr $ra

erase_character:
  addi $sp, $sp, -4
  sw $ra, 0($sp)
  
  jal get_player_address
  move $t4, $v0
  
  sw $zero, 0($t4)              # $zero = 0 = black
  jal erase_trajectory
  
  lw $ra, 0($sp)
  addi $sp, $sp, 4
  jr $ra

erase_held_bubbles:
  addi $sp, $sp, -12
  sw   $ra, 0($sp)
  sw   $s0, 4($sp)              # counter
  sw   $s1, 8($sp)              # bound
  
  lw $s1, HELD_COUNT
  beqz $s1, erase_held_bubbles_done
  li $s0, 0

erase_held_bubbles_loop:
  bge $s0, $s1, erase_held_bubbles_done
  move $a0, $s0
  jal get_held_address
  sw   $zero, 0($v0)
  addi $s0, $s0, 1
  j erase_held_bubbles_loop
  
erase_held_bubbles_done:
  lw   $ra, 0($sp)
  lw   $s0, 4($sp)
  lw   $s1, 8($sp)
  addi $sp, $sp, 12
  jr $ra


# paint the held stack
draw_held_bubbles:
  addi $sp, $sp, -20
  sw   $ra, 0($sp)
  sw   $s0, 4($sp)              # counter
  sw   $s1, 8($sp)              # bound (HELD_COUNT)
  sw   $s2, 12($sp)             # color (HELD_COLOR)
  
  jal  erase_held_bubbles      # clear previous frame first

  lw $s1, HELD_COUNT
  beqz $s1, draw_held_bubbles_done  # If none held, nothing to draw
  lw $s2, HELD_COLOR
  beqz $s2, draw_held_bubbles_done

  li $s0, 0

draw_held_bubbles_loop:
  bge $s0, $s1, draw_held_bubbles_done
  move $a0, $s0
   jal  get_held_address
  sw   $s2, 0($v0)             # all held bubbles share HELD_COLOR
  addi $s0, $s0, 1
  j    draw_held_bubbles_loop
  
draw_held_bubbles_done:
  lw   $ra, 0($sp)
  lw   $s0, 4($sp)
  lw   $s1, 8($sp)
  lw   $s2, 12($sp)
  addi $sp, $sp, 20
  jr   $ra
  

# $a0 = slot index (0 = nearest player). Returns address in $v0.
get_held_address:
  lw   $t8, ADDR_DSPL
  lw   $t9, DISPLAY_WIDTH

  lw   $v0, START_Y
  lw   $t0, PLAYER_OFFSET_Y
  add  $v0, $v0, $t0
  addi $v0, $v0, 1
  add  $v0, $v0, $a0
  mul  $v0, $v0, $t9

  lw   $t8, START_X
  lw   $t0, PLAYER_OFFSET_X
  add  $t8, $t8, $t0
  add  $v0, $v0, $t8
  sll  $v0, $v0, 2
  lw   $t8, ADDR_DSPL
  add  $v0, $t8, $v0
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

  li $t7, 7   # load 7 columns
  mul $t8, $t6, $t7             # local_row * 7
  add $t8, $t8, $t1             # + local_col ($t1 is player_offset_x)
  addi $t8, $t8, -1
  sll $t8, $t8, 2               # Multiply by 4 bytes (since each cell is a word)
  
  # Load grid cell value
  la $t9, game_grid             # Base address of 7x14 grid
  add $t9, $t9, $t8             # Add byte offset
  lw  $t9, 0($t9)               # Read grid cell
  # Stop if cell is not 0 (black) -> a bubble or border is there
  bnez $t9, trajectory_end

  
  andi $t7, $t4, 1              # Check if row is even or odd. RECALL: $t4 = row counter
  bnez $t7, skip_dash_pixel     # If odd, skip painting (leaves it black)

  # Row-Major Address Calculation for current pixel on screen
  mul $t7, $t4, $s3             # Global Row * DISPLAY_WIDTH
  add $t7, $t7, $t5             # + Global Col
  sll $t7, $t7, 2               # Multiply by 4 bytes per unit
  add $t8, $t0, $t7             # Final memory address

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
  la $t6, game_grid
  li $t2, 0                     # grid row 0 to 13

erase_loop:
  bge $t2, 14, erase_done
  mul $t7, $t2, 7
  add $t7, $t7, $t1
  addi $t7, $t7, -1             # grid column = player X - 1
  sll $t7, $t7, 2
  add $t7, $t6, $t7
  lw $v1, 0($t7)                # color from grid (0 if empty)

  add $t8, $t2, $t5
  addi $t8, $t8, 1              # screen row = START_Y + 1 + row
  mul $t8, $t8, $t3
  add $t8, $t8, $t9
  sll $t8, $t8, 2
  add $t8, $t0, $t8
  sw $v1, 0($t8)

  addi $t2, $t2, 1
  j erase_loop

erase_done:
  jr $ra

  
# --------------------------------------------------------------------------------------------------- DRAWING BUBBLES

# Wrapper: shift everything down, fill a new top row, repaint
add_bubble_row:
  addi $sp, $sp, -4  # Allocate new stack space for $ra
  sw $ra, 0($sp)     # Save this current return address into newly allocated space -- can access this after
  # these functions override $ra after returning
  jal shift_grid_down
  jal fill_top_row
  jal draw_grid

  lw $ra, 0($sp)
  addi $sp, $sp, 4  # Move pointer back up
  jr $ra

# Part 1: grid[i] = grid[i-7] for i = 97 down to 7
# (counting downward so we never overwrite a row before copying it)
shift_grid_down:
  la $t0, game_grid
  li $t1, 97                    # last index = 13*7 + 6

shift_loop:
  blt $t1, 7, shift_done
  sll $t2, $t1, 2
  add $t2, $t0, $t2             # $t2 = &grid[i]
  lw $t3, -28($t2)              # grid[i - 7] (the cell directly above)
  sw $t3, 0($t2)
  addi $t1, $t1, -1
  j shift_loop

shift_done:
  jr $ra

# Part 2a: fill row 0 of the grid with random colors
fill_top_row:
  la $t0, game_grid
  la $t4, BUBBLE_COLORS
  li $t1, 0                     # column counter

fill_loop:
  bge $t1, 7, fill_done
  li $v0, 42                    # syscall 42: random int in [0, $a1)
  li $a0, 0
  li $a1, 4                     # 4 colors
  syscall                       # $a0 = random 0..3
  sll $a0, $a0, 2
  add $a0, $t4, $a0
  lw $t5, 0($a0)                # chosen color
  sll $t2, $t1, 2
  add $t2, $t0, $t2
  sw $t5, 0($t2)                # grid[0][col] = color
  addi $t1, $t1, 1
  j fill_loop

fill_done:
  jr $ra

# Part 2b: paint the whole grid onto the display
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
  mul $t7, $t1, 7
  add $t7, $t7, $t2
  sll $t7, $t7, 2
  add $t7, $t6, $t7
  lw $v1, 0($t7)                # color from grid

  add $t8, $t1, $t5             # screen row
  add $t9, $t2, $t4             # screen col
  mul $t8, $t8, $t3
  add $t8, $t8, $t9
  sll $t8, $t8, 2
  add $t8, $t0, $t8
  sw $v1, 0($t8)

  addi $t2, $t2, 1
  j draw_grid_col

draw_grid_next_row:
  addi $t1, $t1, 1
  j draw_grid_row

draw_grid_done:
  jr $ra


# --------------------------------------------------------------------------------------------------- PLAYER CONTROLS

do_move:
  jal move_player
  j sleep
  
move_player:
  addi $sp, $sp, -4
  sw $ra, 0($sp)

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
  lw $ra, 0($sp)
  addi $sp, $sp, 4
  jr $ra

  
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
  mul $t3, $t2, 7              # row * 7
  add $t3, $t3, $t1            # + col
  sll $t3, $t3, 2              # * 4 bytes
  add $t3, $t3, $t0            # &grid[row][col]
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
  addi $sp, $sp, -4
  sw $ra, 0($sp)

  jal find_lowest_bubble_in_col
  beqz $t0, grab_done

  # If it made it to this point, then it found a valid bubble
  # 1. check if held count exceeds max hold
  lw $t6, HELD_COUNT
  lw $t7, MAX_HOLD
  bge $t6, $t7, grab_done
  # 2. check if same color
  beqz $t6, grab_accept  # if hand empty, then any color is ok
  lw $t5, HELD_COLOR
  bne $t5, $v0, grab_done  # if color is different, reject grab

grab_accept:
  sw $v0, HELD_COLOR
  addi $t6, $t6, 1
  sw $t6, HELD_COUNT

  # clear the bubble's cell 
  lw   $t1, PLAYER_OFFSET_X
  addi $t1, $t1, -1
  mul  $t2, $v1, 7
  add  $t2, $t2, $t1
  sll  $t2, $t2, 2
  la   $t3, game_grid
  add  $t3, $t3, $t2
  sw   $zero, 0($t3)

  # repaint: grid (removes old bubble), player+dashes, held stack
  jal  draw_grid
  jal  draw_character
  jal  draw_held_bubbles
  

grab_done:
  lw   $ra, 0($sp)
  addi $sp, $sp, 4
  jr   $ra

  
  

check_throw:

throw:


get_player_address:
  lw $t0, ADDR_DSPL
  lw $t1, DISPLAY_WIDTH
  lw $t2, START_Y
  lw $t3, PLAYER_OFFSET_Y
  add $t2, $t2, $t3            # global row
  lw $t3, START_X
  lw $t4, PLAYER_OFFSET_X
  add $t3, $t3, $t4            # global col
  mul $t2, $t2, $t1            # row * WIDTH
  add $t2, $t2, $t3            # + col
  sll $t2, $t2, 2              # * 4
  add $v0, $t0, $t2
  jr $ra