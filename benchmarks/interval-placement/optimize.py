"""Exact minimum additive interval cost for fixed camera budget and max gap."""
import math

def select_anchors(costs, views, budget, max_gap, preferred=None):
    if not 2 <= budget <= views or max_gap < 1:
        raise ValueError('Invalid view count, budget or gap')
    if preferred is not None and (len(preferred)!=budget or preferred!=sorted(set(preferred)) or preferred[0]!=0 or preferred[-1]!=views-1):
        raise ValueError('Invalid preferred anchor layout')
    # Primary interval score; only exact ties use distance to preferred anchors.
    dp = {(1,0): (0.0, 0, None)}
    for used in range(2,budget+1):
        for right in range(1,views):
            best=(math.inf,math.inf,None)
            penalty=(right-preferred[used-1])**2 if preferred is not None else 0
            for left in range(max(0,right-max_gap),right):
                previous=dp.get((used-1,left))
                if previous is None: continue
                if (left,right) not in costs:
                    raise ValueError(f'Missing interval cost: {left},{right}')
                value=previous[0]+costs[left,right]
                secondary=previous[1]+penalty
                if (value,secondary)<best[:2]: best=(value,secondary,left)
            if best[2] is not None: dp[used,right]=best
    if (budget,views-1) not in dp:
        raise ValueError('No layout satisfies budget and maximum gap')
    total=dp[budget,views-1][0]
    anchors=[views-1]
    for used in range(budget,1,-1): anchors.append(dp[used,anchors[-1]][2])
    return list(reversed(anchors)),total
