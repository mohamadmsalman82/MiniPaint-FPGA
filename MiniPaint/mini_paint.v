/* Mini Paint
 *
 * Features:
 * - Tools: Pen, Eraser, Fill (Whole page), Box (Outline)
 * - Controls: Size Increase/Decrease, Color Selection
 * - Visuals: 9x9 Mouse Cursor, Active Color Box indicator
 * 
 * How To Use:
 * - Left Click and Press KEY[3] at the same time to click
 * - Press KEY[0] to reset the screen (clears entire screen and centres cursor
 * - Use switches SW[8:0} to set the 9-bit colour, press KEY[1] to confirm colour selection
 * - To use box tool, click and hold KEY[3] at first postion, drag to second postion, then release
 * - HEXs 0, 1, 2 show current tool size in hexadecimal
 * - Hex 3 shows the current tool selected (0 - Box, 1 - Pen, 2 - Erase, 3 - Fill)
 */

module mini_paint(
    input CLOCK_50,
    input [9:0] SW,
    input [3:0] KEY,
    inout PS2_CLK,
    inout PS2_DAT,
    output [9:0] LEDR,
    output [6:0] HEX3, HEX2, HEX1, HEX0,
    output [7:0] VGA_R, VGA_G, VGA_B,
    output VGA_HS, VGA_VS, VGA_BLANK_N, VGA_SYNC_N, VGA_CLK
);

    /*******************************************************************************/
	 /*											Parameters 											  */
	 /*******************************************************************************/
    // Bits needed for X and Y
	 parameter nX = 10;
    parameter nY = 9;
    
    // States for the main FSM
    parameter A = 5'd0, B = 5'd1, C = 5'd2, D = 5'd3, 
              Red = 5'd4, Orange = 5'd5, Yellow = 5'd6, Green = 5'd7, 
              Blue = 5'd8, Purple = 5'd9, Black = 5'd10, White = 5'd11, Gray = 5'd12,
              Pen = 5'd13, Eraser = 5'd14, Fill = 5'd15, Box = 5'd16, 
              IncreaseSize = 5'd17, DecreaseSize = 5'd18,
              DrawCursor = 5'd19;

    // Tool Modes
    parameter TOOL_PEN = 3'd1, TOOL_ERASE = 3'd2, TOOL_FILL = 3'd3, 
              TOOL_BOX = 3'd0;
	
	
	/*******************************************************************************/
	/*										 Wires and Regs											 */
	/*******************************************************************************/
    
    wire Resetn = KEY[0];
    wire [8:0] color;
    wire [9:0] X0, XC;
    wire [8:0] Y0, YC;
    reg  [4:0] y_Q, Y_D; // State registers
    
    // Tools / Colors
    wire [8:0] new_color;
    reg  [8:0] top_color;
    reg  setcol;
    reg  [2:0] tool_mode;
    
    // Drawing Control Signals
    reg write_en_fsm, Lxc, Lyc, Exc, Eyc; 

    // Box Tool Registers
    reg [nX-1:0] box_start_x, box_end_x;
    reg [nY-1:0] box_start_y, box_end_y;
    reg [nX-1:0] rect_x_min, rect_width;
    reg [nY-1:0] rect_y_min, rect_height;
    reg box_active, rect_drawing;
    wire use_rect = (tool_mode == TOOL_BOX) && rect_drawing;

    // Size Registers
    reg [nY-1:0] size;
    localparam [nY-1:0] MIN_SIZE = 9'd1;
    localparam [nY-1:0] MAX_SIZE = 9'd31;

    /*******************************************************************************/
	 /*										 Mouse Handling										  */
	 /*******************************************************************************/
	 
    wire left_button;
    wire signed [10:0] cursor_x_raw;
    wire signed [10:0] cursor_y_raw;
    
    PS2_Mouse mouse_inst (
        .CLOCK_50(CLOCK_50),
        .KEY(KEY),
        .PS2_CLK(PS2_CLK),
        .PS2_DAT(PS2_DAT),
        .left_button(left_button),
        .cursor_x(cursor_x_raw),
        .cursor_y(cursor_y_raw)
    );

    wire [9:0] cursor_x = (cursor_x_raw < 0) ? 10'd0 : (cursor_x_raw > 639) ? 10'd639 : cursor_x_raw[9:0];
    wire [8:0] cursor_y = (cursor_y_raw < 0) ? 9'd0 : (cursor_y_raw > 479) ? 9'd479 : cursor_y_raw[8:0];

    // Mouse Sync Logic
    reg [9:0] prev_mouse_x;
    reg [8:0] prev_mouse_y;
    wire mouse_moved = (cursor_x != prev_mouse_x) || (cursor_y != prev_mouse_y);
    
    always @(posedge CLOCK_50) begin
        prev_mouse_x <= cursor_x;
        prev_mouse_y <= cursor_y;
    end

    // Input Assignments
    assign X0 = cursor_x;
    assign Y0 = cursor_y;
    wire [nX-1:0] X_center;
    wire [nY-1:0] Y_center;
    
    regn UX (X0, KEY[0], 1'b1, CLOCK_50, X_center);
        defparam UX.n = nX;
    regn UY (Y0, KEY[0], 1'b1, CLOCK_50, Y_center);
        defparam UY.n = nY;
	
	 /*******************************************************************************/
	 /*								Color and Size Handling										  */
	 /*******************************************************************************/
	 
    // Color Handling
    assign new_color = SW[8:0];
    regn UC (setcol ? top_color : new_color, KEY[0], setcol | ~KEY[1], CLOCK_50, color);
        defparam UC.n = 9;

    // Click logic for inc/dec size
    wire go = left_button && ~KEY[3];
    reg go_prev;
    wire go_pulse;
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) go_prev <= 1'b0;
        else go_prev <= go;
    end
    assign go_pulse = go & ~go_prev;

    // Size Handling
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            size <= MIN_SIZE;
        end else begin
            if (Y_D == IncreaseSize && go_pulse) begin
                if (size < MAX_SIZE) size <= size + 9'd2;
            end else if (Y_D == DecreaseSize && go_pulse) begin
                if (size > MIN_SIZE) size <= size - 9'd2;
            end
        end
    end
	
		
	/*******************************************************************************/
	/*										 Box Tool Drawing					  					    */
	/*******************************************************************************/
	
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) begin
            box_active <= 0; rect_drawing <= 0;
            box_start_x <= 0; box_start_y <= 0;
            rect_x_min <= 0; rect_y_min <= 0;
            rect_width <= 0; rect_height <= 0;
        end else begin
            if (tool_mode == TOOL_BOX) begin
                if (~KEY[3] && !box_active) begin
                    box_start_x <= X_center;
                    box_start_y <= Y_center;
                    box_active <= 1;
                end
                if (KEY[3] && box_active) begin
                    if (X_center < box_start_x) begin
                        rect_x_min <= X_center; rect_width <= box_start_x - X_center;
                    end else begin
                        rect_x_min <= box_start_x; rect_width <= X_center - box_start_x;
                    end
                    if (Y_center < box_start_y) begin
                        rect_y_min <= Y_center; rect_height <= box_start_y - Y_center;
                    end else begin
                        rect_y_min <= box_start_y; rect_height <= Y_center - box_start_y;
                    end
                    rect_drawing <= 1;
                    box_active <= 0;
                end
                if (y_Q == D) rect_drawing <= 0;
            end else begin
                box_active <= 0; rect_drawing <= 0;
            end
        end
    end

    // Counters for drawing loops
    Up_count U1 ({nX{1'd0}}, CLOCK_50, KEY[0], Lxc, Exc, XC);
        defparam U1.n = nX;
    Up_count U2 ({nY{1'd0}}, CLOCK_50, KEY[0], Lyc, Eyc, YC);
        defparam U2.n = nY;

		  
    /*******************************************************************************/
	 /*										Cursor Drawing											  */
	 /*******************************************************************************/
	 
    wire cursor_done;
    wire cursor_write;
    wire [9:0] cur_draw_x;
    wire [8:0] cur_draw_y;
    wire [8:0] cur_color;
    reg activecursor;

    cursor9x9 my_cursor (
        .Clock(CLOCK_50),
        .Resetn(KEY[0]),
        .draw_en(activecursor),
        .cursor_x(cursor_x),
        .cursor_y(cursor_y),
        .VGA_x(cur_draw_x),
        .VGA_y(cur_draw_y),
        .VGA_color(cur_color),
        .VGA_write(cursor_write),
        .done(cursor_done)
    );

    /*******************************************************************************/
	 /*							     Colour Preview Drawing	    							  */
	 /*******************************************************************************/
	 
    wire [9:0] cb_draw_x;
    wire [8:0] cb_draw_y;
    wire colorbox_write;
    wire colorbox_done;

    colorbox9x9 my_colorbox (
        .Clock(CLOCK_50),
        .Resetn(KEY[0]),
        .color(color),
        .cb_draw_x(cb_draw_x),
        .cb_draw_y(cb_draw_y),
        .colorbox_write(colorbox_write),
        .done(colorbox_done)
    );

    /*******************************************************************************/
	 /*							Toolbar and Drawing FSM (Main FSM)							  */
	 /*******************************************************************************/
	 
    always @(*) begin
        Y_D = A;
        
        case (y_Q)
            A: begin
                // Priority 1: Toolbar/Draw Logic
                if (go) begin
                    if (cursor_y > 50) Y_D = B; // Draw on canvas
                    else begin
                        // Toolbar regions
                        if (cursor_x < 66) Y_D = Box;
                        else if (cursor_x < 108) Y_D = Red;
                        else if (cursor_x < 150) Y_D = Orange;
                        else if (cursor_x < 192) Y_D = Yellow;
                        else if (cursor_x < 234) Y_D = Green;
                        else if (cursor_x < 276) Y_D = Blue;
                        else if (cursor_x < 318) Y_D = Purple;
                        else if (cursor_x < 360) Y_D = Black;
                        else if (cursor_x < 402) Y_D = White;
                        else if (cursor_x < 444) Y_D = Gray;
                        else if (cursor_x < 486) Y_D = Pen;
                        else if (cursor_x < 538) Y_D = Eraser;
                        else if (cursor_x < 572) Y_D = Fill;
                        else if (cursor_x < 606) Y_D = IncreaseSize;
                        else if (cursor_x < 640) Y_D = DecreaseSize;
                        else Y_D = A;
                    end
                end 
                // Priority 2: Box Drawing
                else if (tool_mode == TOOL_BOX && rect_drawing) begin
                    Y_D = B;
                end
                // Priority 3: Cursor Movement
                else if (mouse_moved) begin
                    Y_D = DrawCursor;
                end
                else begin
                    Y_D = A;
                end
            end

            /*Drawing Loops*/
				
				// Draw x
            B: begin
                if (tool_mode == TOOL_FILL) begin
                    // FILL MODE X: 10 to 630
                    // Width = 630 - 10 = 620 pixels
                    if (XC != 10'd620) Y_D = B; else Y_D = C;
                end 
                else if (rect_drawing) begin
                    if (XC != rect_width) Y_D = B; else Y_D = C;
                end 
                else begin
                    if (XC != size-1) Y_D = B; else Y_D = C;
                end
            end
				
				// Draw y
            C: begin
                if (tool_mode == TOOL_FILL) begin
                     // FILL MODE Y: 51 to 470
                     // Height = 470 - 51 = 419 pixels
                     if (YC != 9'd419) Y_D = B; else Y_D = D;
                end 
                else if (rect_drawing) begin
                    if (YC != rect_height) Y_D = B; else Y_D = D;
                end 
                else begin
                    if (YC != size-1) Y_D = B; else Y_D = D;
                end
            end
				
				// Check if we need to draw cursors
            D: begin
                if (mouse_moved) Y_D = DrawCursor;
                else Y_D = A;
            end
            
            // Cursor State
            DrawCursor: begin
                if (cursor_done) Y_D = A;
                else Y_D = DrawCursor;
            end

            // Color/Tool States
            default: Y_D = A;
        endcase
    end

    // FSM Output Logic
    always @(*) begin
        // Defaults
        write_en_fsm = 0; Lxc = 0; Lyc = 0; Exc = 0; Eyc = 0; 
        setcol = 0; activecursor = 0; top_color = 0;

        case (y_Q)
            A: begin Lxc = 1; Lyc = 1; end
            
            B: begin 
                Exc = 1; 
                
                // Write logic based on tool
                if (tool_mode == TOOL_PEN && go) write_en_fsm = 1;
                else if (tool_mode == TOOL_ERASE && go) write_en_fsm = 1;
                else if (tool_mode == TOOL_FILL && go) write_en_fsm = 1; 
                else if (tool_mode == TOOL_BOX && rect_drawing) begin
                      // Box uses size for thickness
                      if (XC < size || (XC + size) >= rect_width || 
                          YC < size || (YC + size) >= rect_height) begin
                            write_en_fsm = 1;
                      end
                end
            end
            
            C: begin Lxc = 1; Eyc = 1; end
            D: begin Lyc = 1; end

            // Colors
            Red:    begin top_color = 9'b111000000; setcol = 1; end
            Orange: begin top_color = 9'b111011000; setcol = 1; end
            Yellow: begin top_color = 9'b111111000; setcol = 1; end
            Green:  begin top_color = 9'b000111000; setcol = 1; end
            Blue:   begin top_color = 9'b000000111; setcol = 1; end
            Purple: begin top_color = 9'b111000111; setcol = 1; end
            Black:  begin top_color = 9'd0;         setcol = 1; end
            White:  begin top_color = 9'b111111111; setcol = 1; end
            Gray:   begin top_color = 9'b100100100; setcol = 1; end

            // Cursor
            DrawCursor: activecursor = 1;
        endcase
    end

    // State Register
    always @(posedge CLOCK_50) begin
        if (!Resetn) y_Q <= A;
        else y_Q <= Y_D;
    end

    // Tool Mode Register
    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0]) tool_mode <= TOOL_PEN;
        else begin
            case (y_Q)
                Pen: tool_mode <= TOOL_PEN;
                Eraser: tool_mode <= TOOL_ERASE;
                Fill: tool_mode <= TOOL_FILL;
                Box: tool_mode <= TOOL_BOX;
            endcase
        end
    end
    
    // LEDs and HEX
    assign LEDR = 10'b0;
	 
	 // Displays current tool
	 hex7seg H3 ({1'b0,tool_mode}, HEX3);
	 
	 // Displays current size
    hex7seg H2 ({3'b0,size[8]}, HEX2);
    hex7seg H1 (size[7:4], HEX1);
    hex7seg H0 (size[3:0], HEX0);

	 /*******************************************************************************/
	 /*										Background Reset 										  */
	 /*******************************************************************************/
	 
	 /*Toolbar ROM*/
	 wire [8:0] toolbar_pixel;
	 reg [15:0] toolbar_addr;
	 
	 toolbar_rom t1 (
		.address(toolbar_addr),
		.clock(CLOCK_50),
		.q(toolbar_pixel));
	 
    reg [18:0] bg_addr;
    reg bg_loading;
    reg write_bg;
    reg [9:0] bg_x;
    reg [9:0] bg_y;
	 reg [8:0] bg_color;

    always @(posedge CLOCK_50) begin
        if (!KEY[0]) begin
            bg_loading <= 1;
            bg_addr <= 0;
        end else if (bg_loading) begin
            write_bg <= 1;
            bg_x <= bg_addr % 640;
            bg_y <= bg_addr / 640;
				
				// Check if need to draw toolbar
				if(bg_y < 45) begin
					bg_color <= toolbar_pixel;
					toolbar_addr <= bg_y * 640 + bg_x;
				end
				else
					bg_color <= 9'b111111111; // Since background is white
					
            bg_addr <= bg_addr + 1;
				
            if (bg_addr == 640*480 - 1) begin
                bg_loading <= 0;
                write_bg <= 0;
            end
        end
    end

    /*******************************************************************************/
	 /*									 VGA Multiplexer 											  */
	 /*******************************************************************************/
	 
    // Decides what to write to the VGA adapter
    reg [9:0] mux_x;
    reg [8:0] mux_y;
    reg [8:0] mux_color;
    reg mux_write;

    always @(*) begin
        // Priority 1: Background Loading
        if (bg_loading) begin
            mux_x = bg_x;
            mux_y = bg_y;
            mux_color = bg_color;
            mux_write = write_bg;
        end
		  
        // Priority 2: Cursor
        else if (cursor_write) begin
            mux_x = cur_draw_x;
            mux_y = cur_draw_y;
            mux_color = cur_color;
            mux_write = 1;
				if(mux_x < 10'd10 & mux_y > 10'd465) mux_write = 0;
        end
		  
        // Priority 3: Color Preivew
        else if (colorbox_write) begin
            mux_x = cb_draw_x;
            mux_y = cb_draw_y;
            mux_color = color;
            mux_write = 1;
        end
		  
        // Priority 4: Drawing Tools (Pen/Erase/Box/FILL)
        else if (write_en_fsm) begin
            // Calculate X/Y based on Tool
            
            if (tool_mode == TOOL_FILL) begin
                // FILL: needs to follow drawing boundary
                // Start X = 10, End X = 630
                // Start Y = 51, End Y = 470
                mux_x = 10'd10 + XC; 
                mux_y = 9'd51 + YC;
            end 
            else if (use_rect) begin
                mux_x = rect_x_min + XC;
                mux_y = rect_y_min + YC;
					 
					 // Clamp rectangle at boundary
					 if(mux_y < 9'd50) mux_y = 9'd51;
					 else if(mux_y > 9'd470) mux_y = 9'd470;
					 
					 if(mux_x < 10'd10) mux_x = 10'd10;
					 else if(mux_x > 10'd630) mux_x = 10'd630;
            end 
            else begin
                // Standard Pen/Eraser
                mux_x = X_center - (size >> 1) + XC;
                mux_y = Y_center - (size >> 1) + YC;
					 
					 // Clamp at boundary
					 if(mux_y < 9'd50) mux_y = 9'd51;
					 else if(mux_y > 9'd470) mux_y = 9'd470;
					 
					 if(mux_x < 10'd10) mux_x = 10'd10;
					 else if(mux_x > 10'd630) mux_x = 10'd630;
            end
            
            // Set Color
            if (tool_mode == TOOL_ERASE) mux_color = 9'b111111111; // White
            else mux_color = color;
            
            mux_write = 1;
        end
        // Default: Do nothing
        else begin
            mux_x = 0; mux_y = 0; mux_color = 0; mux_write = 0;
        end
    end

    /*******************************************************************************/
	 /*										VGA Adapter	 											  */
	 /*******************************************************************************/
	 
    vga_adapter VGA (
        .resetn(KEY[0]),
        .clock(CLOCK_50),
        .color(mux_color),
        .x(mux_x),
        .y(mux_y),
        .write(mux_write),
        .VGA_R(VGA_R),
        .VGA_G(VGA_G),
        .VGA_B(VGA_B),
        .VGA_HS(VGA_HS),
        .VGA_VS(VGA_VS),
        .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N),
        .VGA_CLK(VGA_CLK)
    );

endmodule


/*******************************************************************************/
/*										 n-Bit register				  						    */
/*******************************************************************************/

module regn(R, Resetn, E, Clock, Q);
    parameter n = 8;
    input  [n-1:0] R;
    input           Resetn, E, Clock;
    output reg [n-1:0] Q;
    always @(posedge Clock)
        if (!Resetn) Q <= 0;
        else if (E)  Q <= R;
endmodule

/*******************************************************************************/
/*											Up-counter											    */
/*******************************************************************************/

module Up_count (R, Clock, Resetn, L, E, Q);
    parameter n = 8;
    input  [n-1:0] R;
    input           Clock, Resetn, E, L;
    output reg [n-1:0] Q;
    always @ (posedge Clock)
        if (Resetn == 0) Q <= {n{1'b0}};
        else if (L == 1) Q <= R;
        else if (E)      Q <= Q + 1'b1;
endmodule

/*******************************************************************************/
/*											Hex decoder  											 */
/*******************************************************************************/

module hex7seg (hex, display);
    input  [3:0] hex;
    output [6:0] display;
    reg [6:0] display;
	 
	 // Displays in hexadecimal
    always @ (hex)
        case (hex)
            4'h0: display = 7'b1000000; //0
            4'h1: display = 7'b1111001; //1
            4'h2: display = 7'b0100100; //2
            4'h3: display = 7'b0110000; //3
            4'h4: display = 7'b0011001; //4
            4'h5: display = 7'b0010010; //5
            4'h6: display = 7'b0000010; //6
            4'h7: display = 7'b1111000; //7
            4'h8: display = 7'b0000000; //8
            4'h9: display = 7'b0011000; //9
            4'hA: display = 7'b0001000; //10
            4'hB: display = 7'b0000011; //11
            4'hC: display = 7'b1000110; //12
            4'hD: display = 7'b0100001; //13
            4'hE: display = 7'b0000110; //14
            4'hF: display = 7'b0001110; //15
        endcase
endmodule

/*******************************************************************************/
/*											Draw Cursors 										    */
/*******************************************************************************/

module cursor9x9 (Clock, Resetn, draw_en, cursor_x, cursor_y, VGA_x, VGA_y, VGA_color, VGA_write, done);
	 parameter IN_FILE = "hcursor.mif";
	 
    input Clock, Resetn, draw_en;
    input [9:0] cursor_x;
    input [8:0] cursor_y;
    output reg [9:0] VGA_x;
    output reg [8:0] VGA_y;
    output reg [8:0] VGA_color;
    output reg VGA_write, done;

    reg [6:0] addr;
    wire [8:0] pixel_h, pixel_v;
    
	 
	 /*ROM*/
    // Horizotnal cursor (9x9 and colour depth 9)
    hcursor_rom ch (.address(addr), .clock(Clock), .q(pixel_h));
        defparam ch.INIT_FILE = IN_FILE;
	 
	 // Vertical cursor
    hcursor_rom cv (.address(addr), .clock(Clock), .q(pixel_v));
        defparam cv.INIT_FILE = "vcursor.mif";

    wire [3:0] px = addr % 9;
    wire [3:0] py = addr / 9;
    
    // New cursor positon (what we need to draw)
    wire [9:0] new_v_x = 10'd5; 
    wire [8:0] new_v_y = cursor_y;
    wire [9:0] new_h_x = cursor_x;
    wire [8:0] new_h_y = 9'd475;

    // Old cursor postion (what we need to erase)
    reg [9:0] old_v_x, old_h_x;
    reg [8:0] old_v_y, old_h_y;
    
    reg [2:0] state;
    parameter IDLE=0, ERASEV=1, ERASEH=2, DRAWV=3, DRAWH=4, DONE=5;

    always @(posedge Clock) begin
        if (!Resetn) begin
            state <= IDLE; VGA_write <= 0; addr <= 0; done <= 0;
            old_v_x <= 10'd5; old_v_y <= 9'd0; old_h_x <= 10'd0; old_h_y <= 9'd475;
        end else begin
            case (state)
            IDLE: begin
                done <= 0; VGA_write <= 0;
                if (draw_en) begin addr <= 0; state <= ERASEV; end
            end
				
				// Erase old vertical cursor
            ERASEV: begin
                VGA_x <= old_v_x - 5 + px; VGA_y <= old_v_y - 5 + py;
                VGA_color <= 9'b111111111; VGA_write <= 1;
                if(addr == 80) begin addr <= 0; state <= ERASEH; end else addr <= addr + 1;
            end
				
				// Erase old horizontal cursor
            ERASEH: begin
                VGA_x <= old_h_x - 5 + px; VGA_y <= old_h_y - 5 + py;
                VGA_color <= 9'b111111111; VGA_write <= 1;
                if(addr == 80) begin addr <= 0; state <= DRAWV; end else addr <= addr + 1;
            end
				
				// Draw new vertical cursor
            DRAWV: begin
                VGA_x <= new_v_x - 5 + px; VGA_y <= new_v_y - 5 + py;
                VGA_color <= pixel_v; VGA_write <= 1;
                if(addr == 80) begin addr <= 0; state <= DRAWH; end else addr <= addr + 1;
            end
				
				// Draw new horizontal cursor
            DRAWH: begin
                VGA_x <= new_h_x - 5 + px; VGA_y <= new_h_y - 5 + py;
                VGA_color <= pixel_h; VGA_write <= 1;
                if(addr == 80) begin addr <= 0; state <= DONE; end else addr <= addr + 1;
            end
				
				// Store new cursor postions
            DONE: begin
                VGA_write <= 0; done <= 1;
                old_v_x <= new_v_x; old_v_y <= new_v_y;
                old_h_x <= new_h_x; old_h_y <= new_h_y;
                state <= IDLE;
            end
            endcase
        end
    end
endmodule


/*******************************************************************************/
/*									   	Draw Color Box 										 */
/*******************************************************************************/

module colorbox9x9 (Clock, Resetn, color, cb_draw_x, cb_draw_y, colorbox_write, done);
    input Clock, Resetn;
    input [8:0] color;
    output reg [9:0] cb_draw_x;
    output reg [8:0] cb_draw_y;
    output reg colorbox_write, done;

    reg [8:0] last_color;
    reg color_changed;
	 
	 // Check if colour changed
    always @(posedge Clock) begin
        if (!Resetn) begin last_color <= 0; color_changed <= 0; end
        else begin color_changed <= (color != last_color); last_color <= color; end
    end

    reg [6:0] addr;
    wire [3:0] px = addr % 9;
    wire [3:0] py = addr / 9;
    reg [1:0] state;

    always @(posedge Clock) begin
        if (!Resetn) begin state <= 0; addr <= 0; colorbox_write <= 0; done <= 0; end
        else begin
            case (state)
            0: begin // IDLE
                colorbox_write <= 0; done <= 0;
                if (color_changed) begin addr <= 0; state <= 1; end
            end
            1: begin // DRAW
                cb_draw_x <= px + 1; cb_draw_y <= 9'd471 + py;
                colorbox_write <= 1;
                if (addr == 80) state <= 2; else addr <= addr + 1;
            end
            2: begin // DONE
                colorbox_write <= 0; done <= 1; state <= 0;
            end
            endcase
        end
    end
endmodule

