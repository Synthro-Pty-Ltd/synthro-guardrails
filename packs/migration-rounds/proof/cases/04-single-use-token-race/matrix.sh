# Behaviour matrix for the single-use invite. Sourced by run.sh with $CONTAINER
# and $DB set. A race cannot be tested from one session, so this fires two real
# sessions at the same instant from INSIDE the container (two `docker exec`
# calls from the host can start hundreds of milliseconds apart).

alice=00000000-0000-4000-a000-00000000000a
carol=00000000-0000-4000-a000-00000000000c

docker exec -i "$CONTAINER" sh -s <<EOF
redeem() {
  psql -X -q -U postgres -d $DB \
    -c "SET ROLE authenticated" \
    -c "SELECT set_config('request.jwt.claims', '{\"sub\":\"\$1\",\"role\":\"authenticated\"}', false)" \
    -c "SELECT public.redeem_invite('\$2')" >/dev/null 2>&1
}
redeem $alice race-1 &
redeem $carol race-1 &
wait
redeem $alice no-expiry
true
EOF

count() {
  docker exec "$CONTAINER" psql -X -qtA -U postgres -d "$DB" \
    -c "SELECT count(*) FROM public.redemptions WHERE token = '$1'"
}
race=$(count race-1)
noexp=$(count no-expiry)

total=0; fails=0
total=$((total + 1))
if [ "$race" = "1" ]; then echo "ok    two simultaneous redemptions of one invite: exactly 1 succeeded"
else fails=$((fails + 1)); echo "FAIL  two simultaneous redemptions of one invite: $race succeeded"; fi

total=$((total + 1))
if [ "$noexp" = "0" ]; then echo "ok    an invite with no expiry is refused"
else fails=$((fails + 1)); echo "FAIL  an invite with no expiry was redeemed"; fi

if [ "$fails" = "0" ]; then echo "RESULT CLEAN $((total - fails))/$total"
else echo "RESULT DEFECT $((total - fails))/$total"; fi
