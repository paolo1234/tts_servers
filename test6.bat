echo for /f "tokens=1,2 delims=^|" %%%%a in ('uv run python -c "print('a|b')" 2>nul') do set a=1 
