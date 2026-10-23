module tiny_r2_p5_fault_formal;
  (* anyseq *)logic [ 7:0]       valid;
  (* anyseq *)logic [ 7:0][31:0] addresses;
  (* anyseq *)logic [ 1:0]       local_write;
  (* anyseq *)logic [ 5:0]       instruction;
  (* anyseq *)logic [ 5:0][ 1:0] responses;
  logic [ 3:0]       count;
  logic [31:0]       address;
  logic [1:0] owner, response;
  logic write_access;
  logic found;
  integer expected_owner, expected_write;
  tiny_fault_collector u_dut (
      .local_valid_i         (valid[1:0]),
      .local_addr_i          (addresses[1:0]),
      .local_write_i         (local_write),
      .external_valid_i      (valid[7:2]),
      .external_addr_i       (addresses[7:2]),
      .external_resp_i       (responses),
      .external_instruction_i(instruction),
      .count_o               (count),
      .addr_o                (address),
      .master_o              (owner),
      .write_o               (write_access),
      .resp_o                (response)
  );
  always_comb begin
    assert (count == $countones(valid));
    found          = 0;
    expected_owner = 0;
    expected_write = 0;
    // Enumerate the specified lexicographic order, independently of the
    // collector's packed rank and minimum selection implementation.
    for (integer m = 0; m < 3; m++) begin
      for (integer path = 0; path < 2; path++) begin
        for (integer direction = 0; direction < 2; direction++) begin
          for (integer event_index = 0; event_index < 8; event_index++) begin
            expected_owner = (event_index < 2) ? 0 : ((event_index - 2) / 2);
            expected_write=(event_index<2)?integer'(local_write[event_index]):((event_index-2)%2);
            if(!found && valid[event_index] && expected_owner==m && expected_write==direction &&
               ((event_index<2)?(event_index==path):
                (((event_index<4)&&instruction[event_index-2])?(path==0):(path==1)))) begin
              found = 1;
              assert (owner == 2'(m));
              assert (write_access == 1'(direction));
              assert (address == addresses[event_index]);
              assert (response == ((event_index < 2) ? 2'b10 : responses[event_index-2]));
            end
          end
        end
      end
    end
    if (valid == 0) assert ({address, owner, write_access, response} == 0);
  end
endmodule
