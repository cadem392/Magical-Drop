################# CSC258 Assembly Final Project ###################
# This file contains our implementation of Magical Drop.
#
# Student 1: Cade McNelly, 1011958419
# Student 2: Jay Bharat Mehta, 1011744230
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
.eqv FRAME_ROWS 32

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

.eqv PLAYER_ROW                 30
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

# One byte per board cell.
# 0 = not matched, 1 = matched
match_marks:
    .space 98

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

    jal draw_player
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

##############################################################################
# CHECK GAME OVER
##############################################################################

check_game_over:
    # Check whether any bubble occupies the bottom row.
    # If found, set game_over to 1.

    # Calculate the starting address of the last row (row 13)
    la $t0, board

    li $t1, PLAYFIELD_ROWS
    addiu $t1, $t1, -1

    li $t2, PLAYFIELD_COLS
    mul $t1, $t1, $t2
    sll $t1, $t1, 2

    addu $t0, $t0, $t1

    # Check all 7 cells in the bottom row
    li $t2, PLAYFIELD_COLS

check_game_over_loop:
    lw $t3, 0($t0)

    # Any non-empty cell means game over
    bne $t3, $zero, game_over_reached
    nop

    # Move to the next cell
    addiu $t0, $t0, 4
    addiu $t2, $t2, -1

    bgtz $t2, check_game_over_loop
    nop

    # No bubbles in the bottom row
    jr $ra
    nop

game_over_reached:
    # Set game_over = 1
    li $t3, 1
    sw $t3, game_over

    jr $ra
    nop

##############################################################################
# DETECT VERTICAL MATCHES
##############################################################################

detect_vertical_matches:
    # Find all vertical matches of 3 or more bubbles.
    # Mark matching cells without removing them yet.

    # Clear all 98 match markers.
    la $t0, match_marks
    li $t1, 98

clear_match_marks_loop:
    sb $zero, 0($t0)
    addiu $t0, $t0, 1
    addiu $t1, $t1, -1

    bgtz $t1, clear_match_marks_loop
    nop

    # Prepare board and marker addresses.
    la $t0, board
    la $t1, match_marks

    li $t2, 0                  # Current row

detect_match_row_loop:
    li $t3, 0                  # Current column

detect_match_col_loop:
    # Calculate cell index = row * 7 + column.
    li $t4, PLAYFIELD_COLS
    mul $t5, $t2, $t4
    addu $t5, $t5, $t3

    # Calculate address of first bubble.
    sll $t6, $t5, 2
    addu $t7, $t0, $t6

    # Load the first bubble's colour.
    lw $t8, 0($t7)

    # Empty cells cannot form matches.
    beq $t8, $zero, detect_match_next_col
    nop

    # Compare with bubble one row below.
    lw $t9, 28($t7)
    bne $t8, $t9, detect_match_next_col
    nop

    # Compare with bubble two rows below.
    lw $t9, 56($t7)
    bne $t8, $t9, detect_match_next_col
    nop

    # Three matching bubbles found.
    # Mark all three cells.
    addu $t7, $t1, $t5
    li $t9, 1

    sb $t9, 0($t7)
    sb $t9, 7($t7)
    sb $t9, 14($t7)

detect_match_next_col:
    # Move to the next column.
    addiu $t3, $t3, 1

    li $t4, PLAYFIELD_COLS
    blt $t3, $t4, detect_match_col_loop
    nop

    # Move to the next row.
    addiu $t2, $t2, 1

    # Last starting row is 11 (rows 11, 12, 13).
    li $t4, PLAYFIELD_ROWS
    addiu $t4, $t4, -2

    blt $t2, $t4, detect_match_row_loop
    nop

    jr $ra
    nop

##############################################################################
# REMOVE MATCHED BUBBLES
##############################################################################

remove_marked_bubbles:
    # Remove all bubbles marked by detect_vertical_matches.
    # Redraw the board only if at least one bubble was removed.
    # Return the number of removed bubbles in $v0.

    addiu $sp, $sp, -20
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)
    sw $s3, 0($sp)

    # Initialize pointers
    la $s0, board
    la $s1, match_marks

    # Total number of board cells
    li $s2, 98

    # Number of removed bubbles
    li $s3, 0

remove_marked_loop:
    # Read the match marker
    lbu $t0, 0($s1)

    # Skip cells that are not marked
    beq $t0, $zero, remove_marked_next
    nop

    # Remove the bubble by setting its cell to empty
    sw $zero, 0($s0)

    # Count the removed bubble
    addiu $s3, $s3, 1

remove_marked_next:
    # Move to the next board cell
    addiu $s0, $s0, 4

    # Move to the next match marker
    addiu $s1, $s1, 1

    # Decrease remaining cell count
    addiu $s2, $s2, -1

    bgtz $s2, remove_marked_loop
    nop

    # Only redraw if bubbles were removed
    beq $s3, $zero, remove_marked_finished
    nop

    jal draw_board
    nop

remove_marked_finished:
    # Return number of removed bubbles
    move $v0, $s3

    # Restore registers
    lw $s3, 0($sp)
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addiu $sp, $sp, 20

    jr $ra
    nop

##############################################################################
# PROCESS VERTICAL MATCHES
##############################################################################

process_vertical_matches:
    # Detect and remove all vertical matches of 3+ bubbles.
    # Returns the number of removed bubbles in $v0.

    addiu $sp, $sp, -8
    sw $ra, 4($sp)

    # Find and mark all vertical matches
    jal detect_vertical_matches
    nop

    # Remove marked bubbles and redraw the board
    jal remove_marked_bubbles
    nop

    # Restore return address
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
    # Draw the player and all held bubbles vertically.
    # The stack grows upward from the player.

    addiu $sp, $sp, -20
    sw $ra, 16($sp)
    sw $s0, 12($sp)
    sw $s1, 8($sp)
    sw $s2, 4($sp)
    sw $s3, 0($sp)

    # Clear the reserved holding area and player row.
    # Board rows 1-14 must remain untouched.
    li $s0, 16

draw_player_clear_row:
    li $s1, 0

draw_player_clear_col:
    move $a0, $s0
    addiu $a1, $s1, 1
    li $a2, CELL_EMPTY

    jal draw_unit
    nop

    addiu $s1, $s1, 1
    li $t0, PLAYFIELD_COLS
    blt $s1, $t0, draw_player_clear_col
    nop

    addiu $s0, $s0, 1
    li $t0, PLAYER_ROW
    addiu $t0, $t0, 1
    blt $s0, $t0, draw_player_clear_row
    nop

    # Load player's column.
    lw $s1, player_col

    # Draw pink player at row 30.
    li $a0, PLAYER_ROW
    addiu $a1, $s1, 1
    li $a2, CELL_PLAYER

    jal draw_unit
    nop

    # Load number and colour of held bubbles.
    lw $s2, held_count
    lw $s3, held_colour

    # Nothing to display if no bubbles are held.
    beq $s2, $zero, draw_player_finished
    nop

    beq $s3, $zero, draw_player_finished
    nop

    # Start immediately above the player.
    li $s0, PLAYER_ROW
    addiu $s0, $s0, -1

draw_player_held_loop:
    # Draw one held bubble in the player's column.
    move $a0, $s0
    addiu $a1, $s1, 1
    move $a2, $s3

    jal draw_unit
    nop

    # Move upward and decrease remaining count.
    addiu $s0, $s0, -1
    addiu $s2, $s2, -1

    bgtz $s2, draw_player_held_loop
    nop

draw_player_finished:
    # Restore saved registers.
    lw $s3, 0($sp)
    lw $s2, 4($sp)
    lw $s1, 8($sp)
    lw $s0, 12($sp)
    lw $ra, 16($sp)
    addiu $sp, $sp, 20

    jr $ra
    nop

##############################################################################
# GRAB BUBBLES
##############################################################################

grab_bubbles:
    # Grab consecutive same-coloured bubbles from the
    # bottommost occupied cell of the player's column.
    # Store the collected colour and count.
    # Do not grab again while already holding bubbles.

    addiu $sp, $sp, -8
    sw $ra, 4($sp)

    # Get player's current column
    lw $t0, player_col

    # Start at the bottom row of that column
    la $t1, board
    li $t2, PLAYFIELD_ROWS
    addiu $t2, $t2, -1

    li $t3, PLAYFIELD_COLS
    mul $t4, $t2, $t3
    addu $t4, $t4, $t0
    sll $t4, $t4, 2
    addu $t1, $t1, $t4

grab_find_bottom:
    # Search upward for the lowest occupied bubble
    lw $t5, 0($t1)

    bne $t5, $zero, grab_start
    nop

    # Move one row upward (7 words = 28 bytes)
    addiu $t1, $t1, -28
    addiu $t2, $t2, -1

    bgez $t2, grab_find_bottom
    nop

    # Column is empty
    j grab_bubbles_finished
    nop

grab_start:
    # Load the number of bubbles already held
    lw $t6, held_count

    # If already holding bubbles, only grab the same colour
    beq $t6, $zero, grab_colour_valid
    nop

    lw $t8, held_colour
    bne $t5, $t8, grab_bubbles_finished
    nop

grab_colour_valid:
    # Remember the colour being collected
    sw $t5, held_colour

    # Keep the existing held count and add new bubbles to it

grab_matching_loop:
    # Stop when the next bubble has a different colour
    lw $t7, 0($t1)
    bne $t7, $t5, grab_finish
    nop

    # Remove matching bubble
    sw $zero, 0($t1)

    # Increment collected count
    addiu $t6, $t6, 1

    # Move one row upward
    addiu $t1, $t1, -28
    addiu $t2, $t2, -1

    bgez $t2, grab_matching_loop
    nop

grab_finish:
    # Store the number of collected bubbles
    sw $t6, held_count

    # Redraw the board after grabbing
    jal draw_board
    nop

grab_bubbles_finished:
    lw $ra, 4($sp)
    addiu $sp, $sp, 8

    jr $ra
    nop

##############################################################################
# THROW BUBBLES
##############################################################################

throw_bubbles:
    # Throw held bubbles into the player's current column.
    # Attach them beneath the lowest existing bubble.
    # Do not throw if there is insufficient space.
    # Return 1 on success, 0 otherwise.

    addiu $sp, $sp, -24
    sw $ra, 20($sp)
    sw $s0, 16($sp)
    sw $s1, 12($sp)
    sw $s2, 8($sp)
    sw $s3, 4($sp)
    sw $s4, 0($sp)

    # Read held bubble state
    lw $s0, held_count
    lw $s1, held_colour

    # Cannot throw without held bubbles
    beq $s0, $zero, throw_failed
    nop

    beq $s1, $zero, throw_failed
    nop

    # Get the player's current column
    lw $s2, player_col

    # Start searching from the bottom row
    la $s4, board
    li $s3, PLAYFIELD_ROWS
    addiu $s3, $s3, -1

throw_find_stack:
    # If no occupied cell was found, column is empty
    bltz $s3, throw_position_found
    nop

    # Calculate address of board[row][player_col]
    li $t0, PLAYFIELD_COLS
    mul $t1, $s3, $t0
    addu $t1, $t1, $s2
    sll $t1, $t1, 2
    addu $t2, $s4, $t1

    # Check whether this cell contains a bubble
    lw $t3, 0($t2)
    bne $t3, $zero, throw_position_found
    nop

    # Continue searching upward
    addiu $s3, $s3, -1
    j throw_find_stack
    nop

throw_position_found:
    # Place bubbles in the next row below the stack
    # For an empty column, -1 + 1 = row 0
    addiu $s3, $s3, 1

    # Check that all held bubbles will fit
    addu $t0, $s3, $s0
    li $t1, PLAYFIELD_ROWS

    bgt $t0, $t1, throw_failed
    nop

    # Calculate first placement address
    li $t0, PLAYFIELD_COLS
    mul $t1, $s3, $t0
    addu $t1, $t1, $s2
    sll $t1, $t1, 2
    addu $s4, $s4, $t1

throw_place_loop:
    # Place one held bubble
    sw $s1, 0($s4)

    # Move one row downward in memory
    addiu $s4, $s4, 28
    addiu $s0, $s0, -1

    bgtz $s0, throw_place_loop
    nop

    # Clear held state after successful throw
    sw $zero, held_colour
    sw $zero, held_count

    # Remove the held indicator from the player
    jal draw_player
    nop

    # Immediately detect and remove vertical matches
    jal process_vertical_matches
    nop

    # Redraw the final board state
    jal draw_board
    nop

    # Return successful throw
    li $v0, 1
    j throw_finished
    nop

throw_failed:
    # Keep held bubbles unchanged if throwing failed
    move $v0, $zero

throw_finished:
    lw $s4, 0($sp)
    lw $s3, 4($sp)
    lw $s2, 8($sp)
    lw $s1, 12($sp)
    lw $s0, 16($sp)
    lw $ra, 20($sp)
    addiu $sp, $sp, 24

    jr $ra
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

    li $t0, KEY_W
    beq $t0, $a0, handle_W_press
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
    # Grab bubbles from the player's current column
    jal grab_bubbles
    nop

    # Update the player and held bubble indicator
    jal draw_player
    nop

    j handle_key_finished
    nop

handle_W_press:
    # Throw held bubbles into the current column
    jal throw_bubbles
    nop

    j handle_key_finished
    nop

handle_Q_press:
    # Quit the game when Q is pressed
    j game_over_exit
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

##############################################################################
# GAME OVER EXIT
##############################################################################

game_over_exit:
    # Exit the program when game_over is triggered
    li $v0, 10
    syscall

count_wave_key:
    # Increment moves since the last wave
    lw $t0, moves_since_last_wave
    addiu $t0, $t0, 1

    li $t1, MOVES_PER_WAVE
    bne $t0, $t1, save_wave_count
    nop

    # 10 keys reached: reset counter
    sw $zero, moves_since_last_wave

    # Check before shifting to avoid overwriting bottom-row bubbles
    jal check_game_over
    nop

    lw $t0, game_over
    bne $t0, $zero, game_over_exit
    nop

    # Shift existing bubbles down and generate a new top row
    jal advance_bubble_rows
    nop

    # Check if bubbles reached the bottom
    jal check_game_over
    nop

    lw $t0, game_over
    bne $t0, $zero, game_over_exit
    nop

    j game_loop_draw
    nop

save_wave_count:
    sw $t0, moves_since_last_wave

game_loop_draw:
    # 2a. Check for collisions
    # 2b. Update locations (capsules)
    # 3. Draw the screen

    # Only redraw the player after A or D
    li $t0, KEY_A
    beq $s0, $t0, repaint_player
    nop

    li $t0, KEY_D
    beq $s0, $t0, repaint_player
    nop

    j game_loop_continue
    nop

repaint_player:
    jal draw_player
    nop

game_loop_continue:
    # 4a. Refresh the bubble board
    # The player is drawn separately to avoid flickering.
    jal draw_board
    nop

    # 4b. Sleep approximately 16 milliseconds
    # This targets roughly 60 updates per second.
    li $v0, 32
    li $a0, 16
    syscall

    # 5. Go back to Step 1
    j game_loop
    nop
