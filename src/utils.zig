// Helper functions for character checking
pub fn isHexDigit(char: u8) bool {
    return (char >= '0' and char <= '9') or
        (char >= 'a' and char <= 'f') or
        (char >= 'A' and char <= 'F');
}

pub fn isValidChar(byte: u8) bool {
    // check for printable ASCII characters
    return byte >= 0x21 and byte <= 0x7E;
}
