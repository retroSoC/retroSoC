module read_data_mux
	#(parameter c_apb_num_slaves = 1
	)
	(
	input [c_apb_num_slaves-1:0]	m_apb_psel,
	input [31:0]			m_apb_prdata,
	input [31:0]			m_apb_prdata2,
	input [31:0]			m_apb_prdata3,
	input [31:0]			m_apb_prdata4,
	input [31:0]			m_apb_prdata5,
	input [31:0]			m_apb_prdata6,
	input [31:0]			m_apb_prdata7,
	input [31:0]			m_apb_prdata8,
	input [31:0]			m_apb_prdata9,
	input [31:0]			m_apb_prdata10,
	input [31:0]			m_apb_prdata11,
	input [31:0]			m_apb_prdata12,
	input [31:0]			m_apb_prdata13,
	input [31:0]			m_apb_prdata14,
	input [31:0]			m_apb_prdata15,
	input [31:0]			m_apb_prdata16,               
	output[31:0] 	read_data
	);


assign read_data	 = {32{(m_apb_psel == 16'h0001)}} & m_apb_prdata  |
                          {32{(m_apb_psel == 16'h0002)}} & m_apb_prdata2  |
                          {32{(m_apb_psel == 16'h0004)}} & m_apb_prdata3  |
                          {32{(m_apb_psel == 16'h0008)}} & m_apb_prdata4  |
                          {32{(m_apb_psel == 16'h0010)}} & m_apb_prdata5  |
                          {32{(m_apb_psel == 16'h0020)}} & m_apb_prdata6  |
                          {32{(m_apb_psel == 16'h0040)}} & m_apb_prdata7  |
                          {32{(m_apb_psel == 16'h0080)}} & m_apb_prdata8  |
                          {32{(m_apb_psel == 16'h0100)}} & m_apb_prdata9  |
                          {32{(m_apb_psel == 16'h0200)}} & m_apb_prdata10 |
                          {32{(m_apb_psel == 16'h0400)}} & m_apb_prdata11 |
                          {32{(m_apb_psel == 16'h0800)}} & m_apb_prdata12 |
                          {32{(m_apb_psel == 16'h1000)}} & m_apb_prdata13 |
                          {32{(m_apb_psel == 16'h2000)}} & m_apb_prdata14 |
                          {32{(m_apb_psel == 16'h4000)}} & m_apb_prdata15 |
                          {32{(m_apb_psel == 16'h8000)}} & m_apb_prdata16;



endmodule
