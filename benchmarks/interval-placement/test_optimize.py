import itertools
import unittest
from optimize import select_anchors

class IntervalSelectionTest(unittest.TestCase):
    def test_matches_brute_force(self):
        for views in range(3,9):
            costs={(a,b):float(((a+1)*17+b*13)%31) if b-a>1 else 0.0 for a in range(views) for b in range(a+1,min(views,a+4))}
            for budget in range(2,views+1):
                valid=[]
                for middle in itertools.combinations(range(1,views-1),budget-2):
                    anchors=[0,*middle,views-1]
                    if all(b-a<=3 for a,b in zip(anchors,anchors[1:])):
                        valid.append(sum(costs[a,b] for a,b in zip(anchors,anchors[1:])))
                if not valid:
                    with self.assertRaises(ValueError): select_anchors(costs,views,budget,3)
                else:
                    anchors,value=select_anchors(costs,views,budget,3)
                    self.assertEqual(value,min(valid))
                    self.assertEqual(len(anchors),budget)
                    self.assertEqual((anchors[0],anchors[-1]),(0,views-1))
                    self.assertEqual(len(set(anchors)),budget)
                    self.assertTrue(all(0<b-a<=3 for a,b in zip(anchors,anchors[1:])))
    def test_ties_match_brute_force_preference(self):
        views,budget,gap=8,4,3
        preferred=[0,2,5,7]
        for costs in [{(a,b):0.0 for a in range(views) for b in range(a+1,min(views,a+gap+1))},
                      {(a,b):float((a+b)%3) for a in range(views) for b in range(a+1,min(views,a+gap+1))}]:
            candidates=[]
            for middle in itertools.combinations(range(1,views-1),budget-2):
                anchors=[0,*middle,views-1]
                if all(b-a<=gap for a,b in zip(anchors,anchors[1:])):
                    candidates.append((sum(costs[a,b] for a,b in zip(anchors,anchors[1:])),sum((a-b)**2 for a,b in zip(anchors,preferred))))
            anchors,total=select_anchors(costs,views,budget,gap,preferred)
            self.assertEqual((total,sum((a-b)**2 for a,b in zip(anchors,preferred))),min(candidates))
        zero={(a,b):0.0 for a in range(views) for b in range(a+1,min(views,a+gap+1))}
        self.assertEqual(select_anchors(zero,views,budget,gap,preferred)[0],preferred)

    def test_requires_measured_costs(self):
        with self.assertRaises(ValueError): select_anchors({},5,3,3)

if __name__=='__main__': unittest.main()
