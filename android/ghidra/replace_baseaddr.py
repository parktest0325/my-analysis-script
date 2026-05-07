from ghidra.program.model.address import AddressFactory
from ghidra.program.model.address import AddressSpace

def replace_baseaddr():
    program = getCurrentProgram()
    new_base = 0x400000
    af = program.getAddressFactory()
    space = af.getDefaultAddressSpace()
    new_base_addr = space.getAddress(new_base)
    program.setImageBase(new_base_addr, True)

replace_baseaddr()