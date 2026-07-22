
module spisd_card (
    input  logic sck,
    input  logic cs_n,
    input  logic mosi,
    output logic miso,
    input  logic power_on
);

  localparam BLOCK_SIZE = 512;
  localparam CAPACITY_MB = 16;
  localparam BLOCK_COUNT = CAPACITY_MB * 1024 * 1024 / BLOCK_SIZE;

  typedef enum logic [3:0] {
    STATE_IDLE,
    STATE_READ_CMD,
    STATE_PROCESS_CMD,
    STATE_SEND_RESPONSE,
    STATE_READ_DATA,
    STATE_SEND_DATA
  } state_t;

  typedef enum logic [5:0] {
    CMD0_GO_IDLE_STATE      = 6'h00,
    CMD8_SEND_IF_COND       = 6'h08,
    CMD9_SEND_CSD           = 6'h09,
    CMD10_SEND_CID          = 6'h0A,
    CMD12_STOP_TRANSMISSION = 6'h0C,
    CMD16_SET_BLOCKLEN      = 6'h10,
    CMD17_READ_SINGLE_BLOCK = 6'h11,
    CMD24_WRITE_BLOCK       = 6'h18,
    CMD55_APP_CMD           = 6'h37,
    ACMD41_SD_SEND_OP_COND  = 6'h29
  } command_t;

  typedef struct packed {
    logic [6:0] reserved;
    logic       param_error;
    logic       addr_error;
    logic       erase_seq_error;
    logic       com_crc_error;
    logic       illegal_command;
    logic       erase_reset;
    logic       in_idle_state;
  } r1_response_t;

  // verilog_format: off
  state_t current_state = STATE_IDLE;
  state_t next_state;
  logic [7:0] command_byte;
  logic [5:0] command_index;
  logic [31:0] command_argument;
  logic [2:0] command_byte_counter = 0;
  logic [7:0] data_token;
  logic [31:0] block_address;
  logic [8:0] data_byte_counter; 
  logic [7:0] data_buffer[0:BLOCK_SIZE-1]; 
  logic [7:0] csd_register[0:15]; 
  logic [7:0] cid_register[0:15]; 
  r1_response_t current_r1;
  logic [7:0] spi_shift_out;
  logic [7:0] spi_shift_in;
  logic [2:0] bit_counter = 0;
  logic ocr_high_capacity;
  logic initialized = 0;  
  // verilog_format: on

  initial begin
    current_state = STATE_IDLE;
    current_r1 = {7'h0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1};

    csd_register = '{
        8'h40,
        8'h0E,
        8'h00,
        8'h32,  // CSD
        8'h5B,
        8'h59,
        8'h00,
        8'h00,
        8'h1F,
        8'h7F,
        8'h80,
        8'h0A,
        8'h40,
        8'h00,
        8'h00,
        8'h00
    };

    cid_register = '{
        8'h00,
        8'h01,
        8'h41,
        8'h4D,  // MID/OID
        8'h44,
        8'h2D,
        8'h53,
        8'h44,  // PNM
        8'h53,
        8'h44,
        8'h32,
        8'h47,
        8'h30,
        8'h00,
        8'h00,
        8'h64  // PSV/PRV/SN
    };

    for (int i = 0; i < BLOCK_SIZE; i++) begin
      data_buffer[i] = 8'h00;
    end

    // set block size is 512B
    current_r1.in_idle_state = 1;
  end

  // reset
  always @(posedge power_on) begin
    current_r1.in_idle_state = 1;
    initialized              = 0;
  end

  always_ff @(negedge sck or posedge cs_n) begin
    if (cs_n) begin
      spi_shift_in <= 8'h00;
      bit_counter  <= 0;
    end else if (!cs_n) begin
      spi_shift_in <= {spi_shift_in[6:0], mosi};
      bit_counter  <= bit_counter + 1;

      if (bit_counter == 7) begin
        bit_counter <= 0;
        case (current_state)
          STATE_IDLE: begin
            if (spi_shift_in[7:6] == 2'b01) begin
              command_byte         <= spi_shift_in;
              command_byte_counter <= 1;
              next_state    = STATE_READ_CMD;
              current_state = STATE_READ_CMD;
            end
          end

          STATE_READ_CMD: begin
            case (command_byte_counter)
              1: command_argument[31:24] <= spi_shift_in;
              2: command_argument[23:16] <= spi_shift_in;
              3: command_argument[15:8] <= spi_shift_in;
              4: command_argument[7:0] <= spi_shift_in;
              5: begin  // CRC7+ stop bit
                command_index <= command_byte[5:0];
                current_state = STATE_PROCESS_CMD;
              end
            endcase
            command_byte_counter <= command_byte_counter + 1;
          end

          STATE_READ_DATA: begin
            data_buffer[data_byte_counter] <= spi_shift_in;
            data_byte_counter              <= data_byte_counter + 1;
            if (data_byte_counter == (BLOCK_SIZE - 1)) begin
              current_state = STATE_SEND_RESPONSE;
              prepare_response(8'h05);
            end
          end
        endcase
      end
    end
  end


  always_ff @(posedge sck or posedge cs_n) begin
    if (cs_n) begin
      miso          <= 1'b1;
      spi_shift_out <= 8'hFF;
      current_state <= STATE_IDLE;
    end else if (!cs_n) begin
      if (current_state == STATE_SEND_RESPONSE || current_state == STATE_SEND_DATA) begin
        miso          <= spi_shift_out[7];
        spi_shift_out <= {spi_shift_out[6:0], 1'b1};
        bit_counter   <= bit_counter + 1;
      end else begin
        // other state
        miso <= 1'b1;
      end

      // state handle
      case (current_state)
        STATE_PROCESS_CMD: begin
          process_command(command_index);
        end

        STATE_SEND_RESPONSE: begin
          if (bit_counter == 7) begin
            bit_counter <= 0;
            if (data_token == 0) begin
              // R1 resp xfer done
              current_state = STATE_IDLE;
            end else if (data_token == 8'hFE) begin
              // send data
              current_state = STATE_SEND_DATA;
              spi_shift_out <= data_buffer[0];
            end else if (data_token == 8'h05) begin
              // send data done
              current_state = STATE_IDLE;
            end
          end
        end

        STATE_SEND_DATA: begin
          if (bit_counter == 7) begin
            bit_counter       <= 0;
            data_byte_counter <= data_byte_counter + 1;
            if (data_byte_counter < (BLOCK_SIZE - 1)) begin
              spi_shift_out <= data_buffer[data_byte_counter+1];
            end else begin
              // send fake CRC
              spi_shift_out <= 8'hFF;  // CRC1
              next_state = STATE_SEND_RESPONSE;
              prepare_response(0);  // change to IDLE state
            end
          end
        end
      endcase
    end
  end

  task process_command;
    input logic [5:0] cmd;

    // default resp: no error
    current_r1.com_crc_error   = 0;
    current_r1.illegal_command = 0;
    current_r1.addr_error      = 0;
    current_r1.param_error     = 0;

    case (cmd)
      CMD0_GO_IDLE_STATE: begin
        current_r1.in_idle_state = 1;
        prepare_response(1);  // r1 resp
      end

      CMD8_SEND_IF_COND: begin
        // SD2.0 init check
        if (command_argument[11:8] == 4'b0001) begin  // 2.7-3.6V
          // r7 resp(0x01 + params + CRC)
          spi_shift_out <= {1'b0, current_r1};
          // send complete resp
          next_state = STATE_SEND_RESPONSE;
        end
      end

      CMD9_SEND_CSD: begin
        // send CSD register
        for (int i = 0; i < BLOCK_SIZE; i++) begin
          if (i < 16) data_buffer[i] = csd_register[i];
          else data_buffer[i] = 8'h00;
        end
        prepare_response(1);
        // enter data xfer state
        block_address     = 'x;
        data_byte_counter = 0;
      end

      CMD10_SEND_CID: begin
        // xfer CID register
        for (int i = 0; i < BLOCK_SIZE; i++) begin
          if (i < 16) data_buffer[i] = cid_register[i];
          else data_buffer[i] = 8'h00;
        end
        prepare_response(1);
        // enter data xfer state
        block_address     = 'x;
        data_byte_counter = 0;
      end

      CMD16_SET_BLOCKLEN: begin
        // set data block len
        if (command_argument == BLOCK_SIZE) begin
          prepare_response(1);
        end else begin
          current_r1.param_error = 1;
          prepare_response(1);
        end
      end

      CMD17_READ_SINGLE_BLOCK: begin
        if (command_argument < BLOCK_COUNT) begin
          block_address = command_argument;
          // get data from model or RAM
          prepare_response(1);
          data_byte_counter = 0;
        end else begin
          current_r1.addr_error = 1;
          prepare_response(1);
        end
      end

      CMD24_WRITE_BLOCK: begin
        if (command_argument < BLOCK_COUNT) begin
          block_address     = command_argument;
          current_state     = STATE_READ_DATA;
          data_byte_counter = 0;
        end else begin
          current_r1.addr_error = 1;
          prepare_response(1);
        end
      end

      CMD55_APP_CMD: begin
        if (command_argument == 0) begin
          prepare_response(1);
        end
      end

      ACMD41_SD_SEND_OP_COND: begin
        if (command_argument[30] == 1'b1) begin  // HCS
          ocr_high_capacity        = 1;
          current_r1.in_idle_state = 0;
          initialized              = 1;
        end
        prepare_response(1);
      end

      default: begin
        current_r1.illegal_command = 1;
        prepare_response(1);
      end
    endcase
  endtask

  task prepare_response;
    input logic [7:0] token;

    data_token = token;

    case (token)
      1: begin  // R1-type
        spi_shift_out <= {1'b0, current_r1};
        current_state = STATE_SEND_RESPONSE;
      end

      8'hFE: begin  // data token
        spi_shift_out <= 8'hFE;
        current_state = STATE_SEND_RESPONSE;
      end

      8'h05: begin  // data resp
        spi_shift_out <= 8'h05;
        current_state = STATE_SEND_RESPONSE;
      end

      default: begin
        current_state = STATE_IDLE;
      end
    endcase
  endtask

endmodule
