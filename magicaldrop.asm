################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Cade McNelly, 1011958419
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

.eqv PLAYFIELD_COLS  7
.eqv PLAYFIELD_ROWS  14

.eqv FRAME_COLS 9
.eqv FRAME_ROWS 16

.eqv BITMAP_SIZE_UNITS 32

.eqv CELL_EMPTY      0
.eqv CELL_RED        1
.eqv CELL_GREEN      2
.eqv CELL_BLUE       3
.eqv CELL_YELLOW     4
.eqv CELL_FRAME      5
.eqv CELL_PLAYER     6

.eqv KEY_A           0x61
.eqv KEY_D           0x64
.eqv KEY_S           0x73
.eqv KEY_W           0x77
.eqv KEY_Q           0x71

.eqv PLAYER_COL_OFFSET          0
.eqv PLAYER_SCORE_OFFSET        4
.eqv PLAYER_HELD_COLOUR_OFFSET  8
.eqv PLAYER_HELD_COUNT_OFFSET   12
.eqv PLAYER_STATE_SIZE          16

.eqv PLAYER_ROW                 14
.eqv MOVES_PER_WAVE             10

    .data
##############################################################################
# Immutable Data
##############################################################################
# The address of the bitmap display. Don't forget to connect it!
ADDR_DSPL:
    .word 0x10008000
# The address of the keyboard. Don't forget to connect it!
ADDR_KBRD:
    .word 0xffff0000

bubble_palette:
    .word 0x00000000     # empty / black
    .word 0x00ff0000     # red
    .word 0x0000ff00     # green
    .word 0x000000ff     # blue
    .word 0x00ffff00     # yellow
    .word 0x00777777     # grey
    .word 0x00ff00ba     # player

    .align 2

#Player-State Vars
player_state:
player_col:
    .word 3              # begin in centre column
player_score:
    .word 0
held_colour:
    .word CELL_EMPTY
held_count:
    .word 0

#Game-State Vars
moves_since_last_wave:
    .word 0
game_over:
    .word 0

##############################################################################
# Mutable Data
##############################################################################

    .align 2

# Bubble playfield: 7 columns x 14 rows = 98 cells
# Each cell occupies 4 bytes (one word).
# Cell values:
#   0 = Empty
#   1 = Red
#   2 = Green
#   3 = Blue
#   4 = Yellow
board:
    .space 392              # 98 cells * 4 bytes = 392 bytes

##############################################################################
# Code
##############################################################################
	.text
	.globl main

    # Run the game.
main:
    # Initialize the game
    jal initialize_board
    nop

    jal draw_frame
    nop

    jal draw_board
    nop

    j game_loop
    nop
    
##############################################################################
# DRAW FRAME
##############################################################################
    
draw_frame:
    # Draw the game board frame
    addi $sp, $sp, -16      # Init stack of 16 bytes
    sw   $ra, 12($sp)       # draw_frame calls draw_cell
    sw   $s0, 8($sp)        # Current row
    sw   $s1, 4($sp)        # Frame colour ID
    sw   $s2, 0($sp)        # Current column
    
    li   $s0, 0
    li   $s1, CELL_FRAME
    li   $s2, 0
    
frame_row_loop:
    # If row is 0, draw full row
    beq $s0, $zero, frame_full_row
    
    li   $t0, FRAME_ROWS
    addi $t0, $t0, -1
    
    # If row is frame rows - 1, draw full row
    beq $s0, $t0, frame_full_row
    
    # Middle row:
    # Draw left edge
    move $a0, $s0           # row
    li   $a1, 0             # column
    move $a2, $s1           # CELL_FRAME
    jal  draw_unit
    nop

    # Draw right edge
    move $a0, $s0           # row
    li   $a1, FRAME_COLS    # column
    addi $a1, $a1, -1
    move $a2, $s1           # CELL_FRAME
    jal  draw_unit
    nop

    j frame_next_row
    nop

frame_full_row:
    # Fill a full line of frame (top or bottom)
    # Move saved data into arguments
    move $a0, $s0
    move $a1, $s2
    move $a2, $s1
    jal draw_unit
    nop 
    
    # Increment col by 1 until col >= FRAME_COLS, then next row.
    addiu $s2, $s2, 1       
    li    $t0, FRAME_COLS
    blt   $s2, $t0, frame_full_row
    nop 
    
frame_next_row:
    # Increment row by 1 and call frame_row_loop until rows >= FRAME_ROWS, then finish frame 
    li    $s2, 0
    addiu $s0, $s0, 1

    li  $t0, FRAME_ROWS
    blt $s0, $t0, frame_row_loop
    nop
    
frame_finished:
    # Finish Frame and return to main.
    
    # Restore registers and discard stack frame
    lw   $s2, 0($sp)
    lw   $s1, 4($sp)
    lw   $s0, 8($sp)
    lw   $ra, 12($sp)
    addi $sp, $sp, 16

    jr $ra
    nop
    
##############################################################################
# HELPERS
##############################################################################

##############################################################################
# INITIALIZE BOARD
##############################################################################

initialize_board:
    # Save registers
    addiu $sp, $sp, -12
    sw $ra, 8($sp)
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    # Clear all 98 cells
    la $s0, board
    li $s1, 98

clear_board_loop:
    sw $zero, 0($s0)
    addiu $s0, $s0, 4
    addiu $s1, $s1, -1

    bgtz $s1, clear_board_loop
    nop

    # Generate 4 rows of random bubbles at the top
    li $s0, 0

initialize_rows_loop:
    move $a0, $s0
    jal fill_bubble_row
    nop

    addiu $s0, $s0, 1
    li $t0, 4

    blt $s0, $t0, initialize_rows_loop
    nop

    # Restore registers
    lw $s1, 0($sp)
    lw $s0, 4($sp)
    lw $ra, 8($sp)
    addiu $sp, $sp, 12

    jr $ra
    nop

##############################################################################
# FILL BUBBLE ROW
##############################################################################

fill_bubble_row:
    # Fill a row of the board with random coloured bubbles
    # $a0 = row number (0-13)

    addiu $sp, $sp, -8
    sw $s0, 4($sp)
    sw $s1, 0($sp)

    # Calculate starting address of the requested row
    li $t0, PLAYFIELD_COLS
    mul $t1, $a0, $t0
    sll $t1, $t1, 2

    la $s0, board
    addu $s0, $s0, $t1

    # Generate 7 bubbles
    li $s1, PLAYFIELD_COLS

fill_bubble_loop:
    # Generate random number 0-3
    li $v0, 42
    li $a0, 0
    li $a1, 4
    syscall

    # Convert to colour ID 1-4
    addiu $t0, $a0, 1

    # Store bubble in current cell
    sw $t0, 0($s0)

    # Advance to next cell
    addiu $s0, $s0, 4
    addiu $s1, $s1, -1

    bgtz $s1, fill_bubble_loop
    nop

    # Restore registers
    lw $s1, 0($sp)
    lw $s0, 4($sp)
    addiu $sp, $sp, 8

    jr $ra
    nop

##############################################################################
# DRAW BOARD
##############################################################################

draw_board:
    # Draw the 7x14 bubble grid inside the frame
    # Board rows/columns are offset by 1 for the border

    addiu $sp, $sp, -16
    sw $ra, 12($sp)
    sw $s0, 8($sp)
    sw $s1, 4($sp)
    sw $s2, 0($sp)

    la $s2, board
    li $s0, 0                  # Current row

draw_board_row:
    li $s1, 0                  # Current column

draw_board_col:
    # Load the current cell's colour ID
    lw $a2, 0($s2)

    # Convert board coordinates to bitmap coordinates
    addiu $a0, $s0, 1          # Row + top border
    addiu $a1, $s1, 1          # Column + left border

    # Draw the current cell
    jal draw_unit
    nop

    # Advance to next cell
    addiu $s2, $s2, 4
    addiu $s1, $s1, 1

    li $t0, PLAYFIELD_COLS
    blt $s1, $t0, draw_board_col
    nop

    # Move to next row
    addiu $s0, $s0, 1

    li $t0, PLAYFIELD_ROWS
    blt $s0, $t0, draw_board_row
    nop

    # Restore registers
    lw $s2, 0($sp)
    lw $s1, 4($sp)
    lw $s0, 8($sp)
    lw $ra, 12($sp)
    addiu $sp, $sp, 16

    jr $ra
    nop


##############################################################################
# ADVANCE BUBBLE ROWS
##############################################################################

advance_bubble_rows:
    # Shift every existing bubble down by one row.
    # Fill the new top row with random bubbles.
    # Redraw the updated board.

    addiu $sp, $sp, -8
    sw $ra, 4($sp)

    # Find the address of the last cell in the board.
    la $t0, board
    li $t1, PLAYFIELD_ROWS
    li $t2, PLAYFIELD_COLS

    mul $t3, $t1, $t2
    addiu $t3, $t3, -1
    sll $t3, $t3, 2
    addu $t4, $t0, $t3     # Destination: last cell

    # Source is one row above the destination.
    sll $t5, $t2, 2
    subu $t6, $t4, $t5

    # Number of cells that need to move.
    addiu $t7, $t1, -1
    mul $t7, $t7, $t2

advance_bubble_rows_loop:
    # Copy each bubble into the row below it.
    lw $t8, 0($t6)
    sw $t8, 0($t4)

    # Move backwards through memory.
    addiu $t6, $t6, -4
    addiu $t4, $t4, -4
    addiu $t7, $t7, -1

    bgtz $t7, advance_bubble_rows_loop
    nop

    # Generate a new random top row.
    li $a0, 0
    jal fill_bubble_row
    nop

    # Redraw the updated board.
    jal draw_board
    nop

    lw $ra, 4($sp)
    addiu $sp, $sp, 8

    jr $ra
    nop


get_colour:
    # Return the colour word from bubble_palette from id value
    la $t0, bubble_palette
    sll $t1, $a0, 2         # Multiply the colour id by 4
    add $t0, $t0, $t1       # Add offset to address of bubble palette. Represents address of colour at id entry
    lw  $v0, 0($t0)         # $v0 = colour corresponding to id
    
    jr $ra
    nop

draw_unit:
    # $a0 = row
    # $a1 = column
    # $a2 = cell ID

    addi $sp, $sp, -16
    sw   $ra, 12($sp)
    sw   $a0, 8($sp)         # Save row
    sw   $a1, 4($sp)         # Save column
    sw   $a2, 0($sp)         # Save cell ID
    
    move $a0, $a2            # Move cell ID into $a0 for get_colour
    
    jal get_colour           # $v0 now hold the colour corresponding to cell ID
    
    lw $t0, 8($sp)           # Restore row
    lw $t1, 4($sp)           # Restore column
    
    # Calculate bitmap position:
    # index = row * display_width + column
    li   $t2, BITMAP_SIZE_UNITS
    mul  $t3, $t0, $t2
    addu $t3, $t3, $t1
    sll  $t3, $t3, 2         # Shift left by 2 to preserve the 4 byte size
    
    lw $t4, ADDR_DSPL
    
    addu $t4, $t4, $t3
    sw $v0, 0($t4)          # Write the colour to the bitmap position
    
    lw   $ra, 12($sp)
    addi $sp, $sp, 16
    
    jr $ra
    
##############################################################################
# PLAYER OPS
##############################################################################

draw_player:
    # Unfinished draw player function, still need to paint units around the player with empty cell colour
    # Allocate stack space
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    
    # Load PLayer State
    la $t0, player_state
    lw $t1, PLAYER_COL_OFFSET($t0)

    # Pass in Arguments
    li    $a0, PLAYER_ROW
    addiu $a1, $t1, 1        # Logical column + left border
    li    $a2, CELL_PLAYER
    
    # Draw Player
    jal draw_unit
    nop
    
    # Return stack space
    lw   $ra, 4($sp)
    addi $sp, $sp, 8
    jr   $ra
    nop

##############################################################################
# KEYBOARD OPS
##############################################################################

check_keyboard_inputs:
    lw   $t0, ADDR_KBRD
    lw   $t1, 0($t0)        # Receiver control register
    andi $t1, $t1, 1        # Check ready bit
    
    beq  $t1, $zero, no_key
    nop
    
    lw   $v0, 4($t0)        # Return pressed key
    jr   $ra
    nop
    
no_key:
    move $v0, $zero
    jr   $ra
    nop

handle_key:
    # Handle cases for keys
    # First load return address to the stack
    addi $sp, $sp, -8
    sw   $ra, 4($sp)
    
    beq $a0, $zero, handle_key_finished
    nop

    li $t0, KEY_A
    beq $t0, $a0, handle_A_press
    nop
    
    li $t0, KEY_D
    beq $t0, $a0, handle_D_press
    nop
    
    li $t0, KEY_S
    beq $t0, $a0, handle_S_press
    nop
    
    li $t0, KEY_Q
    beq $t0, $a0, handle_Q_press
    nop
    
    j handle_key_finished
    nop

handle_A_press:
    # branch to key finished if out of bounds, if not decrement player col and finish
    la $t0, player_state
    lw $t1, PLAYER_COL_OFFSET($t0)
    
    beq $t1, 0, handle_key_finished
    
    addi $t1, $t1, -1
    sw   $t1, PLAYER_COL_OFFSET($t0)
    
    j handle_key_finished
    nop
    
handle_D_press:
    # branch to key finished if out of bounds, if not increment player col and finish
    la $t0, player_state
    lw $t1, PLAYER_COL_OFFSET($t0)
    
    li $t2, PLAYFIELD_COLS
    addi $t2, $t2, -1
    
    beq $t1, $t2, handle_key_finished
    
    addi $t1, $t1, 1
    sw   $t1, PLAYER_COL_OFFSET($t0)
    
    j handle_key_finished
    nop
    
handle_S_press:
    j handle_key_finished
    nop
    
handle_Q_press:
    j handle_key_finished
    nop
    
handle_key_finished:
    # Return the stack pointer
    lw $ra, 4($sp)
    addi $sp, $sp, 8
    jr $ra
    nop


game_loop:
    # 1a. Check if key has been pressed
    jal check_keyboard_inputs
    nop

    # Save the key so we can use it after handle_key
    move $s0, $v0

    # 1b. Check which key has been pressed
    move $a0, $s0
    jal handle_key
    nop

    # Count only gameplay keys (A, D, S, W)
    li $t0, KEY_A
    beq $s0, $t0, count_wave_key
    nop

    li $t0, KEY_D
    beq $s0, $t0, count_wave_key
    nop

    li $t0, KEY_S
    beq $s0, $t0, count_wave_key
    nop

    li $t0, KEY_W
    beq $s0, $t0, count_wave_key
    nop

    # Ignore other keys
    j game_loop_draw
    nop

count_wave_key:
    # Increment moves since the last wave
    lw $t0, moves_since_last_wave
    addiu $t0, $t0, 1

    li $t1, MOVES_PER_WAVE
    bne $t0, $t1, save_wave_count
    nop

    # 10 keys reached: reset counter and advance rows
    sw $zero, moves_since_last_wave

    jal advance_bubble_rows
    nop

    j game_loop_draw
    nop

save_wave_count:
    sw $t0, moves_since_last_wave

game_loop_draw:
    # 2a. Check for collisions
    # 2b. Update locations (capsules)
    # 3. Draw the screen
    jal draw_player
    nop

    # 4. Sleep

    # 5. Go back to Step 1
    j game_loop
    nop

