@echo off

"asm68k.exe" /m /k /p tmss.asm, tmss.bin >errors.txt, tmss.sym, tmss.lst
type errors.txt

rem Optionally patch ROM end address and checksum (though they are unused).
rem fixheadr.exe	tmss.bim

pause