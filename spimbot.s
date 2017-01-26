# syscall constants
PRINT_STRING = 4
PRINT_CHAR   = 11
PRINT_INT    = 1

# debug constants
PRINT_INT_ADDR   = 0xffff0080
PRINT_FLOAT_ADDR = 0xffff0084
PRINT_HEX_ADDR   = 0xffff0088

# spimbot constants
VELOCITY       = 0xffff0010
ANGLE          = 0xffff0014
ANGLE_CONTROL  = 0xffff0018
BOT_X          = 0xffff0020
BOT_Y          = 0xffff0024
OTHER_BOT_X    = 0xffff00a0
OTHER_BOT_Y    = 0xffff00a4
TIMER          = 0xffff001c
SCORES_REQUEST = 0xffff1018

TILE_SCAN       = 0xffff0024
SEED_TILE       = 0xffff0054
WATER_TILE      = 0xffff002c
MAX_GROWTH_TILE = 0xffff0030
HARVEST_TILE    = 0xffff0020
BURN_TILE       = 0xffff0058
GET_FIRE_LOC    = 0xffff0028
PUT_OUT_FIRE    = 0xffff0040

GET_NUM_WATER_DROPS   = 0xffff0044
GET_NUM_SEEDS         = 0xffff0048
GET_NUM_FIRE_STARTERS = 0xffff004c
SET_RESOURCE_TYPE     = 0xffff00dc
REQUEST_PUZZLE        = 0xffff00d0
SUBMIT_SOLUTION       = 0xffff00d4

# interrupt constants
BONK_MASK               = 0x1000
BONK_ACK                = 0xffff0060
TIMER_MASK              = 0x8000
TIMER_ACK               = 0xffff006c
ON_FIRE_MASK            = 0x400
ON_FIRE_ACK             = 0xffff0050
MAX_GROWTH_ACK          = 0xffff005c
MAX_GROWTH_INT_MASK     = 0x2000
REQUEST_PUZZLE_ACK      = 0xffff00d8
REQUEST_PUZZLE_INT_MASK = 0x800

.data
# data things go here
.align 2
tile_data:.space 1600

puzzle_data: .space 4096
solution_data: .space 328

plants_to_harvest: .word 0
plants_harvested: .word 0
plants_to_harvest_locations: .space 4000

puzzle_requested: .word 0
puzzle_received: .word 0

fires_to_stop: .word 0
fires_stopped: .word 0
fire_locations: .space 4000

center_row: .word 0
center_column: .word 0

.text
main:
	# go wild
	# the world is your oyster :)
	li		$t4, ON_FIRE_MASK
	or 		$t4, $t4, MAX_GROWTH_INT_MASK
	or 		$t4, $t4, REQUEST_PUZZLE_INT_MASK
	or		$t4, $t4, 1							# global interrupt enable
	mtc0 	$t4, $12							# Enable interrupt mask (status register)

	la 		$t0, tile_data
	sw		$t0, TILE_SCAN

	sw		$0, VELOCITY						# make sure it isn't moving

	# init the tiles with seeds			
	jal 	init_seeding_tiles

infinite:
	sw		$0, VELOCITY						# make sure it isn't moving

	# first check if there are any fires to put out
infinite_stop_fires_loop:
	lw 		$t0, fires_to_stop
	lw 		$t1, fires_stopped
	beq 	$t0, $t1, infinite_stop_fires_done

	# otherwise, we have fires at hand
	mul 	$t2, $t1, 4
	lw 		$t3, fire_locations($t2)

	and 	$a0, $t3, 0xffff 					# $a0 = row index
	srl 	$a1, $t3, 16 						# $a1 = column index
	jal 	move_to_row_column

	sw 		$0, PUT_OUT_FIRE

infinite_stop_fires_increment:
	lw 		$t0, fires_stopped
	add 	$t0, $t0, 1
	sw 		$t0, fires_stopped
	j 		infinite_stop_fires_loop

infinite_stop_fires_done:

	# first check if we don't have much water or seeds so we can request puzzle
infinite_request_puzzle:
	lw 		$t0, puzzle_requested
	beq 	$t0, 1, infinite_request_puzzle_done

	lw 		$t0, GET_NUM_SEEDS
	lw 		$t1, GET_NUM_FIRE_STARTERS
	lw 		$t2, GET_NUM_WATER_DROPS
	blt 	$t0, 10, infinite_request_seeds
	blt 	$t1, 5, infinite_request_fire_starters
	blt 	$t2, 50, infinite_request_water_drops
	j 		infinite_request_puzzle_done

	# otherwise, request a water puzzle
infinite_request_water_drops:
	li 		$t0, 0	 							# 0 for water
	j 		infinite_set_resource_and_request_puzzle
infinite_request_seeds:
	li 		$t0, 1	 							# 1 for seeds
	j 		infinite_set_resource_and_request_puzzle
infinite_request_fire_starters:
	li 		$t0, 2	 							# 2 for fire starters
	j 		infinite_set_resource_and_request_puzzle

infinite_set_resource_and_request_puzzle:
	sw 		$t0, SET_RESOURCE_TYPE
	la 		$t0, puzzle_data
	sw 		$t0, REQUEST_PUZZLE

	li 		$t0, 1
	sw 		$t0, puzzle_requested	 			# flag to indicate we have requested it
	
infinite_request_puzzle_done:

infinite_solve_puzzle:
	lw 		$t0, puzzle_received
	beqz 	$t0, infinite_solve_puzzle_done

	# otherwise, we have a puzzle at hand
	jal 	solve_puzzle

	sw 		$0, puzzle_requested 				# reset requested
	sw 		$0, puzzle_received 				# reset received

infinite_solve_puzzle_done:



	# now check if there are any plants to harvest
infinite_harvest_loop:
	lw 		$t0, plants_to_harvest
	lw 		$t1, plants_harvested
	beq 	$t0, $t1, infinite_harvest_loop_done

	mul 	$t2, $t1, 4
	lw 		$t3, plants_to_harvest_locations($t2)

	and 	$a0, $t3, 0xffff 					# $a0 = row index
	srl 	$a1, $t3, 16 						# $a1 = column index
	jal 	move_to_row_column

	sw 		$0, HARVEST_TILE
	sw 		$0, SEED_TILE

infinite_harvest_loop_increment:
	lw 		$t0, plants_harvested
	add 	$t0, $t0, 1
	sw 		$t0, plants_harvested
	j 		infinite_harvest_loop

infinite_harvest_loop_done:


infinite_continue_one:
	# now start watering the center plant TODO: CHANGE THE WAY CENTER IS (7,2)
	lw 		$a0, center_row
	lw 		$a1, center_column
	jal 	move_to_row_column

	la 		$t0, tile_data
	sw 		$t0, TILE_SCAN

	lw 		$a0, center_row
	lw 		$a1, center_column
	mul 	$t0, $a0, 10 						# $t0 = row * 10
	add 	$t0, $t0, $a1 						# $t0 = (row * 10) + column
	mul		$t0, $t0, 16						# $t0 = offset
	la 		$t1, tile_data
	add 	$t2, $t1, $t0
	lw 		$t3, 0($t2)
	bnez 	$t3, infinite_continue_two
	# otherwise, try to plant a seed because the center became empty
	sw 		$0, SEED_TILE

infinite_continue_two:

	li 		$t0, 5
	sw 		$t0, WATER_TILE

	j	infinite












##### FUNCTION: move_to_row_column started #####
	# arg0 ($a0): row index
	# arg1 ($a1): column index
move_to_row_column:
	add 	$sp, $sp, -12
	sw 		$ra, 0($sp)
	sw 		$s0, 4($sp)
	sw 		$s1, 8($sp)

	move 	$s0, $a0
	move 	$s1, $a1

	move 	$a0, $s0
	jal 	get_y_coordinate
	move 	$a0, $v0
	jal 	loop_to_y_value

	move 	$a0, $s1
	jal 	get_x_coordinate
	move 	$a0, $v0
	jal 	loop_to_x_value

	lw 		$ra, 0($sp)
	lw 		$s0, 4($sp)
	lw 		$s1, 8($sp)
	add 	$sp, $sp, 12

	jr 		$ra
##### FUNCTION: move_to_row_column ended #####

##### FUNCTION: get_x_coordinate started #####
	# arg0 ($a0): column index
	# return ($v0): X-coordinate
get_x_coordinate:
	li 		$t0, 30								# temp value
	mul		$t0, $a0, $t0						# $t0 = column index * 30
	add 	$v0, $t0, 15						# $t0 = (column index * 30) + 15 = X-coordinate of TILE
	jr 		$ra
##### FUNCTION: get_x_coordinate ended #####

##### FUNCTION: get_y_coordinate started #####
	# arg0 ($a0): row index
	# return ($v0): Y-coordinate
get_y_coordinate:
	li 		$t0, 30								# temp value
	mul		$t0, $a0, $t0						# $t0 = row index * 30
	add 	$v0, $t0, 15						# $t0 = (row index * 30) + 15 = Y-coordinate of TILE
	jr 		$ra
##### FUNCTION: get_y_coordinate ended #####

##### FUNCTION: loop_to_x_value started #####
	# arg0 ($a0): x_coordinate to move to
loop_to_x_value:
	lw		$t0, BOT_X 							# $t0 = bot_x coordinate
	bgt		$a0, $t0, check_move_right			# if tile is on right, move bot right
	blt		$a0, $t0, check_move_left			# if tile is on left, move bot left
	# otherwise, we are at the right x location
	j 		loop_to_x_value_done

check_move_right:
	# stop if it is not too far right
	add 	$t1, $t0, 5							# check if bot_x_coordinate + 5 exceeds argument x_coordinate
	bgt		$t1, $a0, loop_to_x_value_done

move_right:
	li 		$t2, 0
	li 		$t3, 1
	sw 		$t2, ANGLE
	sw		$t3, ANGLE_CONTROL
	li 		$t3, 10
	sw		$t3, VELOCITY
	j 		loop_to_x_value


check_move_left:
	# stop if it is not too far right
	add 	$t1, $t0, -5						# check if bot_x_coordinate - 5 exceeds argument x_coordinate
	blt		$t1, $a0, loop_to_x_value_done

move_left:
	li 		$t2, 180
	li 		$t3, 1
	sw 		$t2, ANGLE
	sw		$t3, ANGLE_CONTROL
	li 		$t3, 10
	sw		$t3, VELOCITY
	j 		loop_to_x_value

loop_to_x_value_done:
	sw 		$a0, VELOCITY
	jr 		$ra
##### FUNCTION: loop_to_x_value ended #####

##### FUNCTION: loop_to_y_value started #####
	# arg0 ($a0): y_coordinate to move to
loop_to_y_value:
	lw 		$t0, BOT_Y							# $t0 = bot_y coordinate
	bgt		$t0, $a0, check_move_up				# if argument y value is on top, move bot up
	blt		$t0, $a0, check_move_down			# if argument y value is on bottom, move bot down
	# otherwise, we are at the right y location
	j 		loop_to_y_value_done

check_move_up:
	# stop if it is not too far up
	add 	$t1, $t0, -5						# check if bot_y_coordinate - 5 is less than argument y_coordinate
	blt		$t1, $a0, loop_to_y_value_done

move_up:
	li 		$t2, 270
	li 		$t3, 1
	sw 		$t2, ANGLE
	sw		$t3, ANGLE_CONTROL
	li 		$t3, 10
	sw		$t3, VELOCITY
	j 		loop_to_y_value


check_move_down:
	# stop if it is not too far down
	add 	$t1, $t0, 5							# check if bot_y_coordinate + 5 is greater than argument y_coordinate
	bgt		$t1, $a0, loop_to_y_value_done

move_down:
	li 		$t2, 90
	li 		$t3, 1
	sw 		$t2, ANGLE
	sw		$t3, ANGLE_CONTROL
	li 		$t3, 10
	sw		$t3, VELOCITY
	j 		loop_to_y_value

loop_to_y_value_done:
	sw 		$0, VELOCITY
	jr 		$ra
##### FUNCTION: loop_to_y_value ended #####





##### FUNCTION: get_current_row started #####
	# return ($v0): current ROW
get_current_row:
	lw 		$t0, BOT_Y							# $t0 = bot_y coordinate
	div 	$v0, $t0, 30						# $t0 = $t0 / 30
	jr 		$ra
##### FUNCTION: get_current_row ended #####

##### FUNCTION: get_current_column started #####
	# return ($v0): current COLUMN
get_current_column:
	lw 		$t0, BOT_X							# $t0 = bot_x coordinate
	div 	$v0, $t0, 30						# $t0 = $t0 / 30
	jr 		$ra
##### FUNCTION: get_current_column ended #####




##### FUNCTION: get_state_and_owner started #####
	# arg0 ($a0): row of bot
	# arg1 ($a1): column of bot
	# return ($v0): state of TILE (0 if not growing, 1 if growing)
	# return ($v1): owner of TILE (0 if me, 1 if other bot)
get_state_and_owner:
	la 		$t0, tile_data						# update tile data first
	sw 		$t0, TILE_SCAN

	mul 	$t0, $a0, 10 						# $t0 = row * 10
	add 	$t0, $t0, $a1 						# $t0 = (row * 10) + column
	mul		$t0, $t0, 16						# $t0 = offset
	la 		$t1, tile_data						# $t1 = base address
	add 	$t2, $t1, $t0						# $t2 = base_address + offset
	lw		$v0, 0($t2)							# $v0 = state
	lw 		$v1, 4($t2)							# $v1 = owning bot
	jr 		$ra
##### FUNCTION: get_state_and_owner ended #####






##### FUNCTION: init_seeding_tiles started #####
init_seeding_tiles:
	add 	$sp, $sp, -20
	sw 		$ra, 0($sp)
	sw 		$s0, 4($sp)
	sw 		$s1, 8($sp)
	sw 		$s2, 12($sp)
	sw 		$s3, 16($sp)

find_center_row_column:

	li 		$a0, 7
	li 		$a1, 2
	jal 	move_to_row_column
	li 		$a0, 7
	li  	$a1, 2
	jal 	get_state_and_owner
	beqz 	$v0, find_center_row_column_done

	# otherwise, find another location
	li 		$a0, 2
	li 		$a1, 2
	jal 	move_to_row_column
	li 		$a0, 2
	li  	$a1, 2
	jal 	get_state_and_owner
	beqz 	$v0, find_center_row_column_done

	# otherwise, find another location
	li 		$a0, 2
	li 		$a1, 7
	jal 	move_to_row_column
	li 		$a0, 2
	li  	$a1, 7
	jal 	get_state_and_owner
	beqz 	$v0, find_center_row_column_done

	# otherwise, find another location
	li 		$a0, 7
	li 		$a1, 7
	jal 	move_to_row_column
	li 		$a0, 7
	li  	$a1, 7
	jal 	get_state_and_owner
	beqz 	$v0, find_center_row_column_done

find_center_row_column_done:
	jal 	get_current_row
	move 	$s0, $v0 							# $s0 = initial row
	jal 	get_current_column
	move 	$s1, $v0							# $s1 = initial column

	sw 		$s0, center_row
	sw 		$s1, center_column

try_to_seed_tile_1:
	move 	$s2, $s0 							# $s2 = row
	move 	$s3, $s1 							# $s3 column

	move 	$a0, $s2
	move 	$a1, $s3
	jal 	get_state_and_owner

	move 	$t0, $v0							# $t0 = state
	move 	$t1, $v1							# $t1 = owner

	bnez	$t0, try_to_seed_tile_2
	move 	$a0, $s2
	move 	$a1, $s3
	jal 	move_to_row_column
	sw 		$0, SEED_TILE

try_to_seed_tile_2:
	move 	$s2, $s0
	add 	$s3, $s1, 1 						# check next column

	move 	$a0, $s2
	move 	$a1, $s3
	jal 	get_state_and_owner

	move 	$t0, $v0							# $t0 = state
	move 	$t1, $v1							# $t1 = owner

	bnez	$t0, try_to_seed_tile_3
	move 	$a0, $s2
	move 	$a1, $s3
	jal 	move_to_row_column
	sw 		$0, SEED_TILE

try_to_seed_tile_3:
	move 	$s2, $s0
	add 	$s3, $s1, -1						# check previous column

	move 	$a0, $s2
	move 	$a1, $s3
	jal 	get_state_and_owner

	move 	$t0, $v0							# $t0 = state
	move 	$t1, $v1							# $t1 = owner

	bnez	$t0, try_to_seed_tile_4
	move 	$a0, $s2
	move 	$a1, $s3
	jal 	move_to_row_column
	sw 		$0, SEED_TILE

try_to_seed_tile_4:
	add 	$s2, $s0, 1 						# check row below
	move 	$s3, $s1

	move 	$a0, $s2
	move 	$a1, $s3
	jal 	get_state_and_owner

	move 	$t0, $v0							# $t0 = state
	move 	$t1, $v1							# $t1 = owner

	bnez	$t0, try_to_seed_tile_5
	move 	$a0, $s2
	move 	$a1, $s3
	jal 	move_to_row_column
	sw 		$0, SEED_TILE

try_to_seed_tile_5:
	add 	$s2, $s0, -1 						# check row above
	move 	$s3, $s1

	move 	$a0, $s2
	move 	$a1, $s3
	jal 	get_state_and_owner

	move 	$t0, $v0							# $t0 = state
	move 	$t1, $v1							# $t1 = owner

	bnez	$t0, init_seeding_tiles_done
	move 	$a0, $s2
	move 	$a1, $s3
	jal 	move_to_row_column
	sw 		$0, SEED_TILE

init_seeding_tiles_done:
	lw 		$ra, 0($sp)
	lw 		$s0, 4($sp)
	lw 		$s1, 8($sp)
	sw 		$s2, 12($sp)
	sw 		$s3, 16($sp)
	add 	$sp, $sp, 20

	jr 		$ra
##### FUNCTION: init_seeding_tiles ended #####






##### FUNCTION: solve_puzzle started #####
solve_puzzle:
	add 	$sp, $sp, -4
	sw 		$ra, 0($sp)

	la 		$a0, solution_data
	la 		$a1, puzzle_data
	jal 	recursive_backtracking

	la 		$t0, solution_data
	sw 		$t0, SUBMIT_SOLUTION

	# now clear out the solution struct
	la 		$t0, solution_data
	li 		$t8, 0
swp_clear_sol_struct:
	beq 	$t8, 82, swp_clear_sol_struct_done

	mul 	$t9, $t8, 4
	add 	$t9, $t9, $t0
	sw 		$0, 0($t9)

swp_clear_sol_struct_increment:
	add 	$t8, $t8, 1
	j 		swp_clear_sol_struct

swp_clear_sol_struct_done:

	lw 		$ra, 0($sp)
	add 	$sp, $sp, 4

	jr 		$ra
##### FUNCTION: solve_puzzle ended #####






recursive_backtracking:
  sub   $sp, $sp, 680
  sw    $ra, 0($sp)
  sw    $a0, 4($sp)     # solution
  sw    $a1, 8($sp)     # puzzle
  sw    $s0, 12($sp)    # position
  sw    $s1, 16($sp)    # val
  sw    $s2, 20($sp)    # 0x1 << (val - 1)
                        # sizeof(Puzzle) = 8
                        # sizeof(Cell [81]) = 648

  jal   is_complete
  bne   $v0, $0, recursive_backtracking_return_one
  lw    $a0, 4($sp)     # solution
  lw    $a1, 8($sp)     # puzzle
  jal   get_unassigned_position
  move  $s0, $v0        # position
  li    $s1, 1          # val = 1
recursive_backtracking_for_loop:
  lw    $a0, 4($sp)     # solution
  lw    $a1, 8($sp)     # puzzle
  lw    $t0, 0($a1)     # puzzle->size
  add   $t1, $t0, 1     # puzzle->size + 1
  bge   $s1, $t1, recursive_backtracking_return_zero  # val < puzzle->size + 1
  lw    $t1, 4($a1)     # puzzle->grid
  mul   $t4, $s0, 8     # sizeof(Cell) = 8
  add   $t1, $t1, $t4   # &puzzle->grid[position]
  lw    $t1, 0($t1)     # puzzle->grid[position].domain
  sub   $t4, $s1, 1     # val - 1
  li    $t5, 1
  sll   $s2, $t5, $t4   # 0x1 << (val - 1)
  and   $t1, $t1, $s2   # puzzle->grid[position].domain & (0x1 << (val - 1))
  beq   $t1, $0, recursive_backtracking_for_loop_continue # if (domain & (0x1 << (val - 1)))
  mul   $t0, $s0, 4     # position * 4
  add   $t0, $t0, $a0
  add   $t0, $t0, 4     # &solution->assignment[position]
  sw    $s1, 0($t0)     # solution->assignment[position] = val
  lw    $t0, 0($a0)     # solution->size
  add   $t0, $t0, 1
  sw    $t0, 0($a0)     # solution->size++
  add   $t0, $sp, 32    # &grid_copy
  sw    $t0, 28($sp)    # puzzle_copy.grid = grid_copy !!!
  move  $a0, $a1        # &puzzle
  add   $a1, $sp, 24    # &puzzle_copy
  jal   clone           # clone(puzzle, &puzzle_copy)
  mul   $t0, $s0, 8     # !!! grid size 8
  lw    $t1, 28($sp)
  
  add   $t1, $t1, $t0   # &puzzle_copy.grid[position]
  sw    $s2, 0($t1)     # puzzle_copy.grid[position].domain = 0x1 << (val - 1);
  move  $a0, $s0
  add   $a1, $sp, 24
  jal   forward_checking  # forward_checking(position, &puzzle_copy)
  beq   $v0, $0, recursive_backtracking_skip

  lw    $a0, 4($sp)     # solution
  add   $a1, $sp, 24    # &puzzle_copy
  jal   recursive_backtracking
  beq   $v0, $0, recursive_backtracking_skip
  j     recursive_backtracking_return_one # if (recursive_backtracking(solution, &puzzle_copy))
recursive_backtracking_skip:
  lw    $a0, 4($sp)     # solution
  mul   $t0, $s0, 4
  add   $t1, $a0, 4
  add   $t1, $t1, $t0
  sw    $0, 0($t1)      # solution->assignment[position] = 0
  lw    $t0, 0($a0)
  sub   $t0, $t0, 1
  sw    $t0, 0($a0)     # solution->size -= 1
recursive_backtracking_for_loop_continue:
  add   $s1, $s1, 1     # val++
  j     recursive_backtracking_for_loop
recursive_backtracking_return_zero:
  li    $v0, 0
  j     recursive_backtracking_return
recursive_backtracking_return_one:
  li    $v0, 1
recursive_backtracking_return:
  lw    $ra, 0($sp)
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  lw    $s0, 12($sp)
  lw    $s1, 16($sp)
  lw    $s2, 20($sp)
  add   $sp, $sp, 680
  jr    $ra

forward_checking:
  sub   $sp, $sp, 24
  sw    $ra, 0($sp)
  sw    $a0, 4($sp)
  sw    $a1, 8($sp)
  sw    $s0, 12($sp)
  sw    $s1, 16($sp)
  sw    $s2, 20($sp)
  lw    $t0, 0($a1)     # size
  li    $t1, 0          # col = 0
fc_for_col:
  bge   $t1, $t0, fc_end_for_col  # col < size
  div   $a0, $t0
  mfhi  $t2             # position % size
  mflo  $t3             # position / size
  beq   $t1, $t2, fc_for_col_continue    # if (col != position % size)
  mul   $t4, $t3, $t0
  add   $t4, $t4, $t1   # position / size * size + col
  mul   $t4, $t4, 8
  lw    $t5, 4($a1) # puzzle->grid
  add   $t4, $t4, $t5   # &puzzle->grid[position / size * size + col].domain
  mul   $t2, $a0, 8   # position * 8
  add   $t2, $t5, $t2 # puzzle->grid[position]
  lw    $t2, 0($t2) # puzzle -> grid[position].domain
  not   $t2, $t2        # ~puzzle->grid[position].domain
  lw    $t3, 0($t4) #
  and   $t3, $t3, $t2
  sw    $t3, 0($t4)
  beq   $t3, $0, fc_return_zero # if (!puzzle->grid[position / size * size + col].domain)
fc_for_col_continue:
  add   $t1, $t1, 1     # col++
  j     fc_for_col
fc_end_for_col:
  li    $t1, 0          # row = 0
fc_for_row:
  bge   $t1, $t0, fc_end_for_row  # row < size
  div   $a0, $t0
  mflo  $t2             # position / size
  mfhi  $t3             # position % size
  beq   $t1, $t2, fc_for_row_continue
  lw    $t2, 4($a1)     # puzzle->grid
  mul   $t4, $t1, $t0
  add   $t4, $t4, $t3
  mul   $t4, $t4, 8
  add   $t4, $t2, $t4   # &puzzle->grid[row * size + position % size]
  lw    $t6, 0($t4)
  mul   $t5, $a0, 8
  add   $t5, $t2, $t5
  lw    $t5, 0($t5)     # puzzle->grid[position].domain
  not   $t5, $t5
  and   $t5, $t6, $t5
  sw    $t5, 0($t4)
  beq   $t5, $0, fc_return_zero
fc_for_row_continue:
  add   $t1, $t1, 1     # row++
  j     fc_for_row
fc_end_for_row:

  li    $s0, 0          # i = 0
fc_for_i:
  lw    $t2, 4($a1)
  mul   $t3, $a0, 8
  add   $t2, $t2, $t3
  lw    $t2, 4($t2)     # &puzzle->grid[position].cage
  lw    $t3, 8($t2)     # puzzle->grid[position].cage->num_cell
  bge   $s0, $t3, fc_return_one
  lw    $t3, 12($t2)    # puzzle->grid[position].cage->positions
  mul   $s1, $s0, 4
  add   $t3, $t3, $s1
  lw    $t3, 0($t3)     # pos
  lw    $s1, 4($a1)
  mul   $s2, $t3, 8
  add   $s2, $s1, $s2   # &puzzle->grid[pos].domain
  lw    $s1, 0($s2)
  move  $a0, $t3
  jal get_domain_for_cell
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  and   $s1, $s1, $v0
  sw    $s1, 0($s2)     # puzzle->grid[pos].domain &= get_domain_for_cell(pos, puzzle)
  beq   $s1, $0, fc_return_zero
fc_for_i_continue:
  add   $s0, $s0, 1     # i++
  j     fc_for_i
fc_return_one:
  li    $v0, 1
  j     fc_return
fc_return_zero:
  li    $v0, 0
fc_return:
  lw    $ra, 0($sp)
  lw    $a0, 4($sp)
  lw    $a1, 8($sp)
  lw    $s0, 12($sp)
  lw    $s1, 16($sp)
  lw    $s2, 20($sp)
  add   $sp, $sp, 24
  jr    $ra

is_complete:
  lw    $t0, 0($a0)       # solution->size
  lw    $t1, 0($a1)       # puzzle->size
  mul   $t1, $t1, $t1     # puzzle->size * puzzle->size
  move	$v0, $0
  seq   $v0, $t0, $t1
  jr    $ra

get_unassigned_position:
  li    $v0, 0            # unassigned_pos = 0
  lw    $t0, 0($a1)       # puzzle->size
  mul  $t0, $t0, $t0     # puzzle->size * puzzle->size
  add   $t1, $a0, 4       # &solution->assignment[0]
get_unassigned_position_for_begin:
  bge   $v0, $t0, get_unassigned_position_return  # if (unassigned_pos < puzzle->size * puzzle->size)
  mul  $t2, $v0, 4
  add   $t2, $t1, $t2     # &solution->assignment[unassigned_pos]
  lw    $t2, 0($t2)       # solution->assignment[unassigned_pos]
  beq   $t2, 0, get_unassigned_position_return  # if (solution->assignment[unassigned_pos] == 0)
  add   $v0, $v0, 1       # unassigned_pos++
  j   get_unassigned_position_for_begin
get_unassigned_position_return:
  jr    $ra

convert_highest_bit_to_int:
    move  $v0, $0             # result = 0

chbti_loop:
    beq   $a0, $0, chbti_end
    add   $v0, $v0, 1         # result ++
    sra   $a0, $a0, 1         # domain >>= 1
    j     chbti_loop

chbti_end:
    jr    $ra

is_single_value_domain:
    beq    $a0, $0, isvd_zero     # return 0 if domain == 0
    sub    $t0, $a0, 1	          # (domain - 1)
    and    $t0, $t0, $a0          # (domain & (domain - 1))
    bne    $t0, $0, isvd_zero     # return 0 if (domain & (domain - 1)) != 0
    li     $v0, 1
    jr	   $ra

isvd_zero:	   
    li	   $v0, 0
    jr	   $ra
    
get_domain_for_addition:
    sub    $sp, $sp, 20
    sw     $ra, 0($sp)
    sw     $s0, 4($sp)
    sw     $s1, 8($sp)
    sw     $s2, 12($sp)
    sw     $s3, 16($sp)
    move   $s0, $a0                     # s0 = target
    move   $s1, $a1                     # s1 = num_cell
    move   $s2, $a2                     # s2 = domain

    move   $a0, $a2
    jal    convert_highest_bit_to_int
    move   $s3, $v0                     # s3 = upper_bound

    sub    $a0, $0, $s2	                # -domain
    and    $a0, $a0, $s2                # domain & (-domain)
    jal    convert_highest_bit_to_int   # v0 = lower_bound
	   
    sub    $t0, $s1, 1                  # num_cell - 1
    mul    $t0, $t0, $v0                # (num_cell - 1) * lower_bound
    sub    $t0, $s0, $t0                # t0 = high_bits
    bge    $t0, 0, gdfa_skip0

    li     $t0, 0

gdfa_skip0:
    bge    $t0, $s3, gdfa_skip1

    li     $t1, 1          
    sll    $t0, $t1, $t0                # 1 << high_bits
    sub    $t0, $t0, 1                  # (1 << high_bits) - 1
    and    $s2, $s2, $t0                # domain & ((1 << high_bits) - 1)

gdfa_skip1:	   
    sub    $t0, $s1, 1                  # num_cell - 1
    mul    $t0, $t0, $s3                # (num_cell - 1) * upper_bound
    sub    $t0, $s0, $t0                # t0 = low_bits
    ble    $t0, $0, gdfa_skip2

    sub    $t0, $t0, 1                  # low_bits - 1
    sra    $s2, $s2, $t0                # domain >> (low_bits - 1)
    sll    $s2, $s2, $t0                # domain >> (low_bits - 1) << (low_bits - 1)

gdfa_skip2:	   
    move   $v0, $s2                     # return domain
    lw     $ra, 0($sp)
    lw     $s0, 4($sp)
    lw     $s1, 8($sp)
    lw     $s2, 12($sp)
    lw     $s3, 16($sp)
    add    $sp, $sp, 20
    jr     $ra

get_domain_for_subtraction:
    
    # We highly recommend that you copy in our 
    # solution when it is released on Tuesday night 
    # after the late deadline for Lab7.2
    #
    # If you reach this part before Tuesday night,
    # you can paste your Lab7.2 solution here for now

    li     $t0, 1              
    li     $t1, 2
    mul    $t1, $t1, $a0            # target * 2
    sll    $t1, $t0, $t1            # 1 << (target * 2)
    or     $t0, $t0, $t1            # t0 = base_mask
    li     $t1, 0                   # t1 = mask

gdfs_loop:
    beq    $a2, $0, gdfs_loop_end	
    and    $t2, $a2, 1              # other_domain & 1
    beq    $t2, $0, gdfs_if_end
	   
    sra    $t2, $t0, $a0            # base_mask >> target
    or     $t1, $t1, $t2            # mask |= (base_mask >> target)

gdfs_if_end:
    sll    $t0, $t0, 1              # base_mask <<= 1
    sra    $a2, $a2, 1              # other_domain >>= 1
    j      gdfs_loop

gdfs_loop_end:
    and    $v0, $a1, $t1            # domain & mask
    jr	   $ra

get_domain_for_cell:
    # save registers    
    sub $sp, $sp, 36
    sw $ra, 0($sp)
    sw $s0, 4($sp)
    sw $s1, 8($sp)
    sw $s2, 12($sp)
    sw $s3, 16($sp)
    sw $s4, 20($sp)
    sw $s5, 24($sp)
    sw $s6, 28($sp)
    sw $s7, 32($sp)

    li $t0, 0 # valid_domain
    lw $t1, 4($a1) # puzzle->grid (t1 free)
    sll $t2, $a0, 3 # position*8 (actual offset) (t2 free)
    add $t3, $t1, $t2 # &puzzle->grid[position]
    lw  $t4, 4($t3) # &puzzle->grid[position].cage
    lw  $t5, 0($t4) # puzzle->grid[posiition].cage->operation

    lw $t2, 4($t4) # puzzle->grid[position].cage->target

    move $s0, $t2   # remain_target = $s0  *!*!
    lw $s1, 8($t4) # remain_cell = $s1 = puzzle->grid[position].cage->num_cell
    lw $s2, 0($t3) # domain_union = $s2 = puzzle->grid[position].domain
    move $s3, $t4 # puzzle->grid[position].cage
    li $s4, 0   # i = 0
    move $s5, $t1 # $s5 = puzzle->grid
    move $s6, $a0 # $s6 = position
    # move $s7, $s2 # $s7 = puzzle->grid[position].domain

    bne $t5, 0, gdfc_check_else_if

    li $t1, 1
    sub $t2, $t2, $t1 # (puzzle->grid[position].cage->target-1)
    sll $v0, $t1, $t2 # valid_domain = 0x1 << (prev line comment)
    j gdfc_end # somewhere!!!!!!!!

gdfc_check_else_if:
    bne $t5, '+', gdfc_check_else

gdfc_else_if_loop:
    lw $t5, 8($s3) # puzzle->grid[position].cage->num_cell
    bge $s4, $t5, gdfc_for_end # branch if i >= puzzle->grid[position].cage->num_cell
    sll $t1, $s4, 2 # i*4
    lw $t6, 12($s3) # puzzle->grid[position].cage->positions
    add $t1, $t6, $t1 # &puzzle->grid[position].cage->positions[i]
    lw $t1, 0($t1) # pos = puzzle->grid[position].cage->positions[i]
    add $s4, $s4, 1 # i++

    sll $t2, $t1, 3 # pos * 8
    add $s7, $s5, $t2 # &puzzle->grid[pos]
    lw  $s7, 0($s7) # puzzle->grid[pos].domain

    beq $t1, $s6 gdfc_else_if_else # branch if pos == position

    

    move $a0, $s7 # $a0 = puzzle->grid[pos].domain
    jal is_single_value_domain
    bne $v0, 1 gdfc_else_if_else # branch if !is_single_value_domain()
    move $a0, $s7
    jal convert_highest_bit_to_int
    sub $s0, $s0, $v0 # remain_target -= convert_highest_bit_to_int
    addi $s1, $s1, -1 # remain_cell -= 1
    j gdfc_else_if_loop
gdfc_else_if_else:
    or $s2, $s2, $s7 # domain_union |= puzzle->grid[pos].domain
    j gdfc_else_if_loop

gdfc_for_end:
    move $a0, $s0
    move $a1, $s1
    move $a2, $s2
    jal get_domain_for_addition # $v0 = valid_domain = get_domain_for_addition()
    j gdfc_end

gdfc_check_else:
    lw $t3, 12($s3) # puzzle->grid[position].cage->positions
    lw $t0, 0($t3) # puzzle->grid[position].cage->positions[0]
    lw $t1, 4($t3) # puzzle->grid[position].cage->positions[1]
    xor $t0, $t0, $t1
    xor $t0, $t0, $s6 # other_pos = $t0 = $t0 ^ position
    lw $a0, 4($s3) # puzzle->grid[position].cage->target

    sll $t2, $s6, 3 # position * 8
    add $a1, $s5, $t2 # &puzzle->grid[position]
    lw  $a1, 0($a1) # puzzle->grid[position].domain
    # move $a1, $s7 

    sll $t1, $t0, 3 # other_pos*8 (actual offset)
    add $t3, $s5, $t1 # &puzzle->grid[other_pos]
    lw $a2, 0($t3)  # puzzle->grid[other_pos].domian

    jal get_domain_for_subtraction # $v0 = valid_domain = get_domain_for_subtraction()
    # j gdfc_end
gdfc_end:
# restore registers
    
    lw $ra, 0($sp)
    lw $s0, 4($sp)
    lw $s1, 8($sp)
    lw $s2, 12($sp)
    lw $s3, 16($sp)
    lw $s4, 20($sp)
    lw $s5, 24($sp)
    lw $s6, 28($sp)
    lw $s7, 32($sp)
    add $sp, $sp, 36    
    jr $ra

clone:

    lw  $t0, 0($a0)
    sw  $t0, 0($a1)

    mul $t0, $t0, $t0
    mul $t0, $t0, 2 # two words in one grid

    lw  $t1, 4($a0) # &puzzle(ori).grid
    lw  $t2, 4($a1) # &puzzle(clone).grid

    li  $t3, 0 # i = 0;
clone_for_loop:
    bge  $t3, $t0, clone_for_loop_end
    sll $t4, $t3, 2 # i * 4
    add $t5, $t1, $t4 # puzzle(ori).grid ith word
    lw   $t6, 0($t5)

    add $t5, $t2, $t4 # puzzle(clone).grid ith word
    sw   $t6, 0($t5)
    
    addi $t3, $t3, 1 # i++
    
    j    clone_for_loop
clone_for_loop_end:

    jr  $ra













.kdata											# interrupt handler data (separated just for readability)
chunkIH:	.space 20							# space for registers

.ktext 0x80000180
interrupt_handler:
.set noat
	move	$k1, $at							# Save $at                               
.set at
	la		$k0, chunkIH
	sw		$a0, 0($k0)							# Get some free registers                  
	sw		$a1, 4($k0)							# by storing them to a global variable
	sw 		$s0, 8($k0)
	sw 		$s1, 12($k0)    
	sw 		$ra, 16($k0) 

	mfc0	$k0, $13							# Get Cause register                       
	srl		$a0, $k0, 2                
	and		$a0, $a0, 0xf						# ExcCode field                            
	bne		$a0, 0, done         

interrupt_dispatch:								# Interrupt:                             
	mfc0	$k0, $13							# Get Cause register, again                 
	beq		$k0, 0, done						# handled all outstanding interrupts     

	and		$a0, $k0, ON_FIRE_MASK				# is there a on fire interrupt?                
	bne		$a0, 0, on_fire_interrupt

	and		$a0, $k0, MAX_GROWTH_INT_MASK		# is there a on max growth interrupt?                
	bne		$a0, 0, on_max_growth_interrupt

	and		$a0, $k0, REQUEST_PUZZLE_INT_MASK	# is there a on puzzle request interrupt?                
	bne		$a0, 0, on_puzzle_request_interrupt

	j		done

on_fire_interrupt:
	sw		$a1, ON_FIRE_ACK					# acknowledge interrupt

	lw 		$s0, fires_to_stop
	add 	$a1, $s0, 1
	sw 		$a1, fires_to_stop

	lw 		$s1, GET_FIRE_LOC
	mul 	$s0, $s0, 4
	sw 		$s1, fire_locations($s0)

	j		interrupt_dispatch					# see if other interrupts are waiting

on_max_growth_interrupt:
	sw		$a1, MAX_GROWTH_ACK					# max growth interrupt

	lw 		$s0, plants_to_harvest
	add 	$a1, $s0, 1
	sw 		$a1, plants_to_harvest

	lw 		$s1, MAX_GROWTH_TILE
	mul 	$s0, $s0, 4
	sw 		$s1, plants_to_harvest_locations($s0)

	j		interrupt_dispatch					# see if other interrupts are waiting

on_puzzle_request_interrupt:
	sw		$a1, REQUEST_PUZZLE_ACK				# puzzle request interrupt

	li 		$s0, 1
	sw 		$s0, puzzle_received

	j		interrupt_dispatch					# see if other interrupts are waiting

done:
	la		$k0, chunkIH
	lw		$a0, 0($k0)							# Restore saved registers
	lw		$a1, 4($k0)
	lw 		$s0, 8($k0)
	lw 		$s1, 12($k0)
	lw 		$ra, 16($k0)
.set noat
	move	$at, $k1							# Restore $at
.set at 
	eret
