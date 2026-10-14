# Viola-Jones-Face-Detection-framework-accelerator
A hardware accelerator of classification part of Viola-Jones face detection algorithm implemented on the Zybo Z7-10 FPGA. This project includes system modeling in SystemC, RTL design in VHDL, functional verification with UVM, and Linux driver development.

Each one of the aforementioned stages is independently executable and verifiable as of now. The folders are listed as follows:

**data**: input data for the classifier.

**docs**: documentation on the classifier, one document for each stage of development of the device.

**driver_app**: driver and application for executing the classification on the Zybo Z7-10 FPGA board.

**hls**: Vitis HLS-compatible C code, mandatory step when converting high-level C++ code to RTL.

**rtl_hdl**: RTL implementation of the accelerator.

**spec**: project specification, including C++ and MATLAB implementations of the Viola-Jones algorithm and bit-accurate analysis using SystemC.

**uvm**: UVM environment for functional verification of the accelerator.

**vp**: Virtual platform implemented using a SystemC model.

A note that the RTL design diverges from the implemented virtual platform due to limitations of the Zybo Z7-10 board which was the target platform of this project. For more detailed information on this, please check the documentation folder.
