/*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                              Overview
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++/
A design to decode a framed data based on the shared spec.
The design is accompanied by a simulation environment as well as a Quartus envionement to generate bitfile and test on a Stratix10 FPGA hardware.
The pin assignemt is not done as it depends on the target FPGA device.

/*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                             Project Structure
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++/

LMS_assignment/
├── design/
│   ├── msg_parser.sv
│   │      # The message parser design 
│   ├── msg_parser_v2
│          # A second implmentation sligtly diffrent than the 1st one. In this implementation,
│          # it is assumed that all bytes are valid unless we are starting a new packet
│       
├── README.txt
│
├── tb/
│   ├── Makefile
│   │       # A makefile to run the simulation. Modelsim/Questasim was used for this purpose
│   ├── top.sv
|   |       # A top level design file used to drive the data/control signals for the msg_parser 
|   |       # than check the validity of the decoded data
|   └── files.vc
|           # Contain the list of files/macros for compilation
|
├── mem_files/
|          # contains memory initialization files, for the encoded data, control
|          #  signals and the expected data to be compared against the decoded data
|
└── hardware/
|   A Quartus evironment to run synthesis, P&R, STA, and bitfile generation 
│   ├── Makefile
|   |
|   ├── msg_parser.qsf
|   |
|   ├── msg_parser.qpf
|   |
|   ├── waveform:
|      # The obtained waveform after testing the design on a stratix10 FPGA based hardware
|      # to visualize the waveform, run: sh view_waveform.sh
|   
└── sdc/
    # contains the sdc constraint file of the design



/*++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
                              Assumptions
+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++/

1) Master-Slave TREADY/TVALID handshake: TREADY before TVALID handshake

2) The master reset depends or uses the same reset as the slave.

3) Invalid bytes (tkeep = 0) reside at the end of the transfer.
   Example: tkeep = 00111111, or tkeep = 00001111
   It is assumed that such configuration is not allowed: tkeep = 10111111 or tkeep = 10101111

4) It is assumed that the 2 bytes reserved for msg_count are always located at the beginning of a transfer. I.e: s_tdata[15:0]
