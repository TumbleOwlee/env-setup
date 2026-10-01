#!/usr/bin/env bash

count=$(checkupdates 2>/dev/null | wc -l)

echo "%{T1}%{T-} %{T2}$count%{T-}"
