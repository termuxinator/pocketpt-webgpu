python3 html_merger.py index_cpp_input.html

pcpp pocketpt_ne.js -D %1 --line-directive > pocketpt_pcpp.js

pcpp index_cpp_input_merged.html --line-directive > index_cpp_output_%1.html

del /Q pocketpt_pcpp.js
del /Q index_cpp_input_merged.html