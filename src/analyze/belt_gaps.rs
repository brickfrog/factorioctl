//! Belt gap detection for finding breaks in belt networks

use std::collections::HashMap;
use crate::world::{Entity, TilePos};
use super::{BeltGap, BeltGapResult, BeltGraph, GapType};

/// Analyze belt network for gaps (missing, misaligned, or blocked connections)
pub fn find_belt_gaps(graph: &BeltGraph, all_entities: &[Entity]) -> BeltGapResult {
    // Build entity lookup for non-belt entities
    let entity_at: HashMap<TilePos, &Entity> = all_entities
        .iter()
        .filter(|e| !e.name.contains("belt"))
        .map(|e| (e.position.to_tile(), e))
        .collect();

    let mut gaps = Vec::new();

    for (pos, node) in graph.iter() {
        let output_pos = node.output_tile();

        // Check if this belt has no downstream connection
        if graph.downstream_of(pos).is_empty() {
            // There's a potential gap - what's at the output position?
            if let Some(target_belt) = graph.get(&output_pos) {
                // There IS a belt there, but no connection - must be misaligned
                gaps.push(BeltGap {
                    from: *pos,
                    to: output_pos,
                    from_direction: node.direction,
                    gap_type: GapType::Misaligned,
                    blocker: Some(format!(
                        "{} facing {:?}",
                        target_belt.belt_type, target_belt.direction
                    )),
                });
            } else if let Some(blocker) = entity_at.get(&output_pos) {
                // Non-belt entity blocking the path
                gaps.push(BeltGap {
                    from: *pos,
                    to: output_pos,
                    from_direction: node.direction,
                    gap_type: GapType::Blocked,
                    blocker: Some(blocker.name.clone()),
                });
            } else {
                // Nothing there at all - missing belt
                gaps.push(BeltGap {
                    from: *pos,
                    to: output_pos,
                    from_direction: node.direction,
                    gap_type: GapType::Missing,
                    blocker: None,
                });
            }
        }
    }

    BeltGapResult {
        gap_count: gaps.len() as u32,
        gaps,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::{Direction, Position};

    fn make_belt(x: i32, y: i32, dir: Direction) -> Entity {
        Entity {
            unit_number: Some((x * 100 + y) as u32),
            name: "transport-belt".to_string(),
            entity_type: Some("transport-belt".to_string()),
            position: Position::new(x as f64 + 0.5, y as f64 + 0.5),
            direction: dir.to_factorio(),
            health: Some(100.0),
            force: Some("player".to_string()),
        }
    }

    fn make_entity(x: i32, y: i32, name: &str) -> Entity {
        Entity {
            unit_number: Some((x * 1000 + y) as u32),
            name: name.to_string(),
            entity_type: Some(name.to_string()),
            position: Position::new(x as f64 + 0.5, y as f64 + 0.5),
            direction: 0,
            health: Some(100.0),
            force: Some("player".to_string()),
        }
    }

    #[test]
    fn test_no_gaps() {
        let entities = vec![
            make_belt(0, 0, Direction::East),
            make_belt(1, 0, Direction::East),
            make_belt(2, 0, Direction::East),
        ];

        let graph = BeltGraph::from_entities(&entities);
        let result = find_belt_gaps(&graph, &entities);

        // Only the last belt has a "gap" (endpoint)
        assert_eq!(result.gap_count, 1);
        assert_eq!(result.gaps[0].gap_type, GapType::Missing);
        assert_eq!(result.gaps[0].from, TilePos::new(2, 0));
    }

    #[test]
    fn test_missing_gap() {
        let entities = vec![
            make_belt(0, 0, Direction::East),
            // Gap at (1, 0)
            make_belt(2, 0, Direction::East),
        ];

        let graph = BeltGraph::from_entities(&entities);
        let result = find_belt_gaps(&graph, &entities);

        // Belt at (0,0) has gap, belt at (2,0) has endpoint gap
        assert_eq!(result.gap_count, 2);

        let gap_0 = result.gaps.iter().find(|g| g.from == TilePos::new(0, 0)).unwrap();
        assert_eq!(gap_0.gap_type, GapType::Missing);
        assert_eq!(gap_0.to, TilePos::new(1, 0));
    }

    #[test]
    fn test_misaligned_gap() {
        let entities = vec![
            make_belt(0, 0, Direction::East),
            make_belt(1, 0, Direction::West), // Facing wrong way!
        ];

        let graph = BeltGraph::from_entities(&entities);
        let result = find_belt_gaps(&graph, &entities);

        // Belt at (0,0) outputs to (1,0) but belt there faces wrong way
        let gap = result.gaps.iter().find(|g| g.from == TilePos::new(0, 0)).unwrap();
        assert_eq!(gap.gap_type, GapType::Misaligned);
    }

    #[test]
    fn test_blocked_gap() {
        let entities = vec![
            make_belt(0, 0, Direction::East),
            make_entity(1, 0, "stone-furnace"),
        ];

        let graph = BeltGraph::from_entities(&entities);
        let result = find_belt_gaps(&graph, &entities);

        let gap = result.gaps.iter().find(|g| g.from == TilePos::new(0, 0)).unwrap();
        assert_eq!(gap.gap_type, GapType::Blocked);
        assert_eq!(gap.blocker, Some("stone-furnace".to_string()));
    }
}
