for /f "tokens=1,2 delims=^|" %%a in ('uv run python -c "import torch; torch.cuda.is_available^()"') do (echo %%a)
