//! Belt graph data structure for connectivity analysis

use std::collections::HashMap;
use crate::world::{Direction, Entity, TilePos};

/// A belt entity with connectivity information
#[derive(Debug, Clone)]
pub struct BeltNode {
    pub unit_number: Option<u32>,
    pub position: TilePos,
    pub direction: Direction,
    pub belt_type: String,
}

impl BeltNode {
    /// Get the tile this belt outputs to (downstream)
    pub fn output_tile(&self) -> TilePos {
        self.position.offset_in_direction(self.direction)
    }

    /// Get the tile this belt primarily receives from (upstream, opposite direction)
    pub fn primary_input_tile(&self) -> TilePos {
        self.position.offset_in_direction(self.direction.opposite())
    }

    /// Get side-loading input tiles (perpendicular to belt direction)
    pub fn side_input_tiles(&self) -> [TilePos; 2] {
        [
            self.position.offset_in_direction(self.direction.rotate_ccw()),
            self.position.offset_in_direction(self.direction.rotate_cw()),
        ]
    }
}

/// Belt graph for connectivity analysis
pub struct BeltGraph {
    /// All belts indexed by position
    nodes: HashMap<TilePos, BeltNode>,
    /// Forward edges: position -> downstream positions that receive from this belt
    downstream: HashMap<TilePos, Vec<TilePos>>,
    /// Reverse edges: position -> upstream positions that feed this belt
    upstream: HashMap<TilePos, Vec<TilePos>>,
}

impl BeltGraph {
    /// Build belt graph from a list of entities
    pub fn from_entities(entities: &[Entity]) -> Self {
        let mut nodes = HashMap::new();

        // First pass: collect all belt nodes
        for entity in entities {
            if !entity.name.contains("belt") {
                continue;
            }

            let position = entity.position.to_tile();
            let direction = Direction::from_factorio(entity.direction);

            nodes.insert(
                position,
                BeltNode {
                    unit_number: entity.unit_number,
                    position,
                    direction,
                    belt_type: entity.name.clone(),
                },
            );
        }

        // Second pass: build edges
        let mut downstream: HashMap<TilePos, Vec<TilePos>> = HashMap::new();
        let mut upstream: HashMap<TilePos, Vec<TilePos>> = HashMap::new();

        for (pos, node) in &nodes {
            let output = node.output_tile();

            // Check if there's a belt at the output position
            if let Some(target) = nodes.get(&output) {
                // The target belt must be able to receive from this direction
                // A belt can receive from: behind (primary) or sides (side-loading)
                let can_receive = {
                    let target_input = target.primary_input_tile();
                    let [side_left, side_right] = target.side_input_tiles();
                    *pos == target_input || *pos == side_left || *pos == side_right
                };

                if can_receive {
                    downstream.entry(*pos).or_default().push(output);
                    upstream.entry(output).or_default().push(*pos);
                }
            }
        }

        Self {
            nodes,
            downstream,
            upstream,
        }
    }

    /// Get belt at position
    pub fn get(&self, pos: &TilePos) -> Option<&BeltNode> {
        self.nodes.get(pos)
    }

    /// Check if position contains a belt
    pub fn contains(&self, pos: &TilePos) -> bool {
        self.nodes.contains_key(pos)
    }

    /// Get downstream neighbors (where items flow to)
    pub fn downstream_of(&self, pos: &TilePos) -> &[TilePos] {
        self.downstream.get(pos).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Get upstream neighbors (where items come from)
    pub fn upstream_of(&self, pos: &TilePos) -> &[TilePos] {
        self.upstream.get(pos).map(|v| v.as_slice()).unwrap_or(&[])
    }

    /// Get all belt positions in the graph
    pub fn all_positions(&self) -> impl Iterator<Item = &TilePos> {
        self.nodes.keys()
    }

    /// Get all belt nodes
    pub fn iter(&self) -> impl Iterator<Item = (&TilePos, &BeltNode)> {
        self.nodes.iter()
    }

    /// Number of belts in the graph
    pub fn len(&self) -> usize {
        self.nodes.len()
    }

    /// Check if graph is empty
    pub fn is_empty(&self) -> bool {
        self.nodes.is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::world::Position;

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

    #[test]
    fn test_straight_line() {
        // Three belts in a row going east: (0,0) -> (1,0) -> (2,0)
        let entities = vec![
            make_belt(0, 0, Direction::East),
            make_belt(1, 0, Direction::East),
            make_belt(2, 0, Direction::East),
        ];

        let graph = BeltGraph::from_entities(&entities);

        assert_eq!(graph.len(), 3);

        // Check downstream connections
        let p0 = TilePos::new(0, 0);
        let p1 = TilePos::new(1, 0);
        let p2 = TilePos::new(2, 0);

        assert_eq!(graph.downstream_of(&p0), &[p1]);
        assert_eq!(graph.downstream_of(&p1), &[p2]);
        assert!(graph.downstream_of(&p2).is_empty());

        // Check upstream connections
        assert!(graph.upstream_of(&p0).is_empty());
        assert_eq!(graph.upstream_of(&p1), &[p0]);
        assert_eq!(graph.upstream_of(&p2), &[p1]);
    }

    #[test]
    fn test_side_loading() {
        // Belt going east at (1,0), with side-loader from south at (1,1)
        let entities = vec![
            make_belt(1, 0, Direction::East),
            make_belt(1, 1, Direction::North), // Side-loading from south
        ];

        let graph = BeltGraph::from_entities(&entities);

        let main = TilePos::new(1, 0);
        let side = TilePos::new(1, 1);

        // Side belt should connect to main belt
        assert_eq!(graph.downstream_of(&side), &[main]);
        assert_eq!(graph.upstream_of(&main), &[side]);
    }
}
