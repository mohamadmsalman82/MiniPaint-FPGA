module PS2_Mouse (
	// Inputs
	CLOCK_50,
	KEY,

	// Bidirectionals
	PS2_CLK,
	PS2_DAT,
	
	// Outputs
	left_button,
	cursor_x,
	cursor_y
);

/*****************************************************************************
 *                           Parameter Declarations                          *
 *****************************************************************************/


/*****************************************************************************
 *                             Port Declarations                             *
 *****************************************************************************/

// Inputs
input				CLOCK_50;
input		[3:0]	KEY;

// Bidirectionals
inout				PS2_CLK;
inout				PS2_DAT;

// Outputs
output reg left_button;

output reg signed [10:0]	cursor_x;
output reg signed	[10:0]	cursor_y;

/*****************************************************************************
 *                 Internal Wires and Registers Declarations                 *
 *****************************************************************************/

// Internal Wires
wire		[7:0]	ps2_key_data;
wire				ps2_key_pressed;

// Internal Registers
reg[7:0]	last_data_received;
reg [7:0] mouse_packet [2:0];
reg[1:0] byte_count;
reg signed [7:0] x_movement; //needs to be signed since x can be signed
reg signed [7:0] y_movement; //same as x
reg right_button;

reg middle_button;


// State Machine Registers

/*****************************************************************************
 *                         Finite State Machine(s)                           *
 *****************************************************************************/


/*****************************************************************************
 *                             Sequential Logic                              *
 *****************************************************************************/
 
always @(posedge CLOCK_50)
begin
	if (KEY[0] == 1'b0) begin
		byte_count <= 0;
		x_movement <= 8'sh00; // sh for signed
		y_movement <= 8'sh00; // sh for signed
		right_button <= 1'b0;
		left_button <= 1'b0;
		middle_button <= 1'b0;
		cursor_x	<= 10'sd320;
		cursor_y	<= 10'sd240;
	end else if (ps2_key_pressed) begin
		mouse_packet[byte_count] <= ps2_key_data;
			// Read left, right and middle clicks
			if(byte_count == 1 & mouse_packet[0][7] != 1'b1 & mouse_packet[0][6] != 1'b1) begin
				right_button <= mouse_packet[0][1]; // Right button is byte 0, bit 1
				left_button <= mouse_packet[0][0]; // Left button is byte 0, bit 0
				middle_button <= mouse_packet[0][2]; // Middle button is byte 0, bit 2
			end
			
			// Read X and Y movements 
			if (byte_count == 3) begin // Now have received the whole mouse packet
				if(mouse_packet[0][3] == 1'b1) begin
					if(mouse_packet[0][6] != 1'b1)begin // x overflow only update y
						
						y_movement <= $signed(mouse_packet[2]); // y is stored in byte 2 $signed type casts to treat it as a signed when its not
						
						cursor_y	<= cursor_y - y_movement; 
						
						if (cursor_y < 4) cursor_y <= 4;
						else if (cursor_y > 466) cursor_y <= 466; // for 640x480 resolution
						
					end
					if(mouse_packet[0][7] != 1'b1) begin // y overflow only update x
						
						x_movement <= $signed(mouse_packet[1]); // x is stored in byte 1		

						cursor_x	<= cursor_x + x_movement;

						
						if (cursor_x < 16) cursor_x <= 16;
						else if (cursor_x > 639) cursor_x <= 639; // for 640x480 resolution
					end
					//end
				end
			byte_count <= 0;
		end
			else begin
				byte_count <= byte_count + 2'b01;
			end
		end
end

/*****************************************************************************
 *                            Combinational Logic                            *
 *****************************************************************************/


/*****************************************************************************
 *                              Internal Modules                             *
 *****************************************************************************/

PS2_Controller #(.INITIALIZE_MOUSE(1)) PS2 (
	// Inputs
	.CLOCK_50				(CLOCK_50),
	.reset				(~KEY[0]),

	// Bidirectionals
	.PS2_CLK			(PS2_CLK),
 	.PS2_DAT			(PS2_DAT),

	// Outputs
	.received_data		(ps2_key_data),
	.received_data_en	(ps2_key_pressed)
);


endmodule





